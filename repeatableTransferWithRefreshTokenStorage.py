import os
import argparse
import datetime as dt

from globus_sdk import (
        TransferClient,
        TransferData,
        NativeAppAuthClient, 
        RefreshTokenAuthorizer,
        TransferAPIError
)
from globus_sdk.scopes import TransferScopes
from globus_sdk.tokenstorage import SimpleJSONFileAdapter

# Matt Pritchard, June 2024
# Adapted from 
# https://globus-sdk-python.readthedocs.io/en/stable/examples/group_listing.html#example-group-listing-with-token-storage
# and
# https://globus-sdk-python.readthedocs.io/en/stable/tutorial.html#tutorial-step5
# and additional examples from Josh Hampton, NCAS.
# 
# Demonstrates OAuth2 flow with refresh tokens, combined with proactive checking of consent needed for 
# specific collections.
#
# Further examples here
# https://globus-sdk-python.readthedocs.io/en/stable/examples/index.html

parser = argparse.ArgumentParser()
parser.add_argument("SRC")
parser.add_argument("DST")
args = parser.parse_args()

current_time = dt.datetime.now()

# Register your own app at developers.globus.org and use **YOUR OWN** CLIENT_ID here
CLIENT_ID = "YOUR OWN CLIENT ID HERE" # REPLACE

AUTH_CLIENT = NativeAppAuthClient(CLIENT_ID)
MY_FILE_ADAPTER = SimpleJSONFileAdapter(
    os.path.expanduser("~/.globus-transfer-tokens.json")
)

def do_login_flow(scopes=TransferScopes.all):
    AUTH_CLIENT.oauth2_start_flow(
        requested_scopes=scopes,
        refresh_tokens=True,
    )
    authorize_url = AUTH_CLIENT.oauth2_get_authorize_url()
    print(f"Please go to this URL and login:\n\n{authorize_url}\n")
    auth_code = input("Please enter the code here: ").strip()
    tokens = AUTH_CLIENT.oauth2_exchange_code_for_tokens(auth_code)
    return tokens


if not MY_FILE_ADAPTER.file_exists():
    # do a login flow, getting back initial tokens
    response = do_login_flow()
    # now store the tokens and pull out the relevant ones for the TransferClient
    MY_FILE_ADAPTER.store(response)
    by_rs = response.by_resource_server
    tokens = by_rs[TransferClient.resource_server]
else:
    # otherwise, we already did login; load the tokens from that file
    tokens = MY_FILE_ADAPTER.get_token_data(TransferClient.resource_server)

# construct the RefreshTokenAuthorizer which writes back to storage on refresh
authorizer = RefreshTokenAuthorizer(
    tokens["refresh_token"],
    AUTH_CLIENT,
    access_token=tokens["access_token"],
    expires_at=tokens["expires_at_seconds"],
    on_refresh=MY_FILE_ADAPTER.on_refresh,
)
# use that authorizer to authorize the activity of the transfer client
transfer_client = TransferClient(authorizer=authorizer)

# Now we have a client, we could interact with any collection that 
# doesn't require specific consent. However most do.

# So, try an ls on the source and destination to see if ConsentRequired
# errors are raised
consent_required_scopes = []
def check_for_consent_required(tc, target):
    try:
        tc.operation_ls(target, path="/")
    # catch all errors and discard those other than ConsentRequired
    # e.g. ignore PermissionDenied errors as not relevant
    except TransferAPIError as err:
        if err.info.consent_required:
            consent_required_scopes.extend(err.info.consent_required.required_scopes)

check_for_consent_required(transfer_client, args.SRC)
check_for_consent_required(transfer_client, args.DST)

# the block above may or may not populate this list
# but if it does, handle ConsentRequired with a new login

if consent_required_scopes:
    print(
        "One of your endpoints requires consent in order to be used.\n"
        "Trying second login to grant consents.\n\n"
    )
    scopes_list = [TransferScopes.all] + consent_required_scopes
    response = do_login_flow(scopes_list)
    MY_FILE_ADAPTER.store(response)
    transfer_client = TransferClient(authorizer=authorizer)


# From this point onwards, the logic can be replaced with what's needed
# for the specific transfer operation required: the example here just
# transfers 1 file from source to destination, but applies a labelled time-stamp
# The login / consent flow above however now means that this can be repeated
# indefinitely, without need for interactive re-authentication, so could be 
# used for repeated / sync tasks.

task_data = TransferData(
    source_endpoint=args.SRC, destination_endpoint=args.DST,
    label = f"SDK transfer w/ collection consent - {current_time.strftime('%Y%m%dT%H%M%S')}"
)
task_data.add_item(
    "/~/src.dat",  # source
    "/~/dst.dat",  # dest
)


def do_submit(client):
    task_doc = client.submit_transfer(task_data)
    task_id = task_doc["task_id"]
    print(f"submitted transfer, task_id={task_id}")


try:
    do_submit(transfer_client)
except TransferAPIError as err:
    if err.info.consent_required:
        print(
            "Consent error: one or more collection requires consent, please login again."
        )
    elif (err.info.authorization_parameters and err.info.authorization_parameters.session_required_single_domain):
        print(err.info.authorization_parameters.session_message," : ",err.info.authorization_parameters.session_required_single_domain)
        print(
            f"Your authentication with domain {err.info.authorization_parameters.session_required_single_domain} needs to be refreshed. Please go to https://app.globus.org and navigate to the collection manually to re-authenticate, then retry here."
        )
    else:
        print(
            "A transfer API error occurred\n",
            err
        )
