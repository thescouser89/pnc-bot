# ******************************************************************************
# pnc irc extension for hubot
#
# Current commands implemented:
# ----------------------------
# 1. pnc-bot: running builds  -> list running builds on main_pnc_server
#                                (defined in hubot-pnc.json)
#
# 2. pnc-bot: pnc status      -> list the server status used for PNC
#                                (define the servers to check in hubot-pnc.json)
#
# Author: dcheung
#
# ******************************************************************************

# ==============================================================================
# Begin: Import statements
# ==============================================================================
# Used to check if server is online
Rest = require("restler")

# Used to measure time elapsed
Elapsed = require("elapsed")

# Used to parse config file
JSON_File = require("jsonfile")

# this will make string be able to be formatted with IRC color
require("irc-colors").global()

# Cronjob
CronJob = require('cron').CronJob
# ==============================================================================
# End: Import statements
# ==============================================================================

# ==============================================================================
# Begin: Global variables
# ==============================================================================

# Disable SSL check
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0"

status_online = "Online"
status_online_errors = "Online, but throwing errors"
status_offline = "OFFLINE"

config_file = "hubot-pnc.json"
test_pnc_online_url = "/pnc-rest/rest/users"
test_indy_online_url = "/api/remote/central/xom/xom/"
test_da_online_url = "/da/rest/v-1"

config = ''

pnc_servers = []
indy_servers = []
jenkins_servers = []
keycloak_servers = []
dependency_analysis_servers = []
repour_servers = []
scrum_users = []
# ==============================================================================
# End: Global variables
# ==============================================================================

# ==============================================================================
# Parse the configuration file and set initial values for hte global variables
# ==============================================================================
JSON_File.readFile(config_file, (err, obj) ->
  config = obj

  pnc_servers = config.pnc_servers
  indy_servers = config.indy_servers
  jenkins_servers = config.jenkins_servers
  keycloak_servers = config.keycloak_servers
  dependency_analysis_servers = config.dependency_analysis_servers
  repour_servers = config.repour_servers
  scrum_users = config.scrum_users
)

# ==============================================================================
# Beginning of bot
# ==============================================================================
module.exports = (robot) ->

  # Keep the current state of the servers
  # server_status = {
  #   "server_name": "online",
  #   "server_name2": "offline"
  # }
  server_status = {}

  # ============================================================================
  # Colorize the string based on the status
  # ============================================================================
  irc_colorize_status = (status) ->
    switch status
      when status_online then status.irc.green.bold()
      when status_online_errors then status.irc.yellow.bold.bgblack()
      when status_offline then status.irc.red.bold.bgwhite()

  # ============================================================================
  # Print to the channel that a server has changed status
  #
  # Parameters:
  #   server_url: :string:
  #   new_status: :string:
  #   old_status: :string:
  # ============================================================================
  notify_status_change = (server_url, new_status, old_status) ->

    opening_msg = ">>>".irc.bold.red()
    closing_msg = "<<<".irc.bold.red()
    message = "#{opening_msg} #{server_url} is now #{irc_colorize_status(new_status)}" +
              " (was previously #{irc_colorize_status(old_status)}) #{closing_msg}"

    robot.messageRoom config.pnc_monitoring_channel, message

  # ============================================================================
  # Check if the Keycloak server is online
  #
  # Parameters:
  #   keycloak url: :string:
  #   handler: function accepting 2 parameters, first one is server url, second one is status
  # ============================================================================
  check_keycloak_server = (keycloak_url, handler, retries = 2) ->

    request =
      data:
        grant_type: 'password'
        client_id: config.keycloak_config.client_id
        username: config.keycloak_config.username
        password: config.keycloak_config.password


    realm = config.keycloak_config.realm

    Rest.post("#{keycloak_url}/auth/realms/#{realm}/protocol/openid-connect/token", request).on('success', (result) ->

      # we got logged in, we need to logout now
      request_response =
        data:
          client_id: config.keycloak_config.client_id
          refresh_token: result.refresh_token

      option = {'headers': {'Authorization': 'Bearer ' + result.access_token}}

      Rest.post("#{keycloak_url}/auth/realms/#{realm}/protocol/openid-connect/logout",
                request_response, option)

      handler keycloak_url, status_online

    ).on('fail', (result) ->
      handler keycloak_url, status_online_errors if retries == 0
      check_keycloak_server(keycloak_url, handler, retries - 1) if retries != 0
    ).on('error', (result) ->
      handler keycloak_url, status_offline if retries == 0
      check_keycloak_server(keycloak_url, handler, retries - 1) if retries != 0
    )

  # ============================================================================
  # Check if the Repour server is online
  #
  # Parameters:
  #   repour url: :string:
  #   handler: function accepting 2 parameters, first one is server url, second one is status
  # ============================================================================
  check_repour_server = (repour_url, handler, retries = 2) ->
    Rest.get(repour_url).on('404', (result) ->
      handler repour_url, status_online
    ).on('503', (result) ->
      handler repour_url, status_online_errors if retries == 0
      check_repour_server(repour_url, handler, retries - 1) if retries != 0
    ).on('error', (result) ->
      handler repour_url, status_offline if retries == 0
      check_repour_server(repour_url, handler, retries - 1) if retries != 0
    )

  # ============================================================================
  # General check for status of server
  #
  # This is the generic implementation to see if a server is online or not
  # Does a GET on server_url_test (note: expects full URL)
  #
  # Parameters:
  #   server url: :string:
  #   handler: :function: function accepting 2 parameters, first one is server url, second one is status
  # ============================================================================
  check_status_server = (server_url, server_url_test, handler, retries = 2) ->

    Rest.get(server_url_test).on('success', (result) ->
      handler server_url, status_online
    ).on('fail', (result) ->
      handler server_url, status_online_errors if retries == 0
      check_status_server(server_url, server_url_test, handler, retries - 1) if retries != 0
    ).on('error', (result) ->
      handler server_url, status_offline if retries == 0
      check_status_server(server_url, server_url_test, handler, retries - 1) if retries != 0
    )

  # ============================================================================
  # Handler for the check_* functions
  #
  # Update the current status of the channel, and notify to the channel
  # if the status has changed
  #
  # Parameters:
  #   server_url: :string:
  #   status    : :string: current status of the server
  # ============================================================================
  update_status = (server_url, status) ->
    if server_status[server_url]
      if server_status[server_url] != status
        robot.logger.info "#{server_url} is #{status}"
        notify_status_change server_url, status, server_status[server_url]
        server_status[server_url] = status
    else
      # first time the server is encountered, don't notify
      robot.logger.info "#{server_url} is #{status}"
      server_status[server_url] = status

  # ============================================================================
  # Function generating a handler for the check_* functions
  #
  # Immediately notify the user of the current status of the server. This
  # function returns a new function that will act as the handler for the check_*
  # functions
  #
  # Parameters:
  #   server_type: :string: type of the server
  #   res        : IRC object to return the final string to the sender
  # ============================================================================
  reply_now = (server_type, res) ->
      (server_url, status) ->
        status_colorized = irc_colorize_status(status)
        res.send "#{server_type.irc.grey()} :: #{server_url} : #{status_colorized}"

  # ============================================================================
  # Simple cronjob to remind people it's scrum-time!
  # ============================================================================
  crontime = () ->
    users_str = config.scrum_users.join(' ')
    message = "IT'S SCRUM TIME !!! IT'S SCRUM TIME !!! IT'S SCRUM TIME !!!".irc.rainbow.bold()
    message += " " + config.scrum_extra_notes
    robot.messageRoom config.pnc_monitoring_channel, users_str + ": " + message

  new CronJob("0 43-44 9 * * 1-4", crontime, null, true)
  # ============================================================================
  # *==* Update this function if you want to add a new server monitoring! *==*
  # Function invoked in the cron job
  # ============================================================================
  cron_check_status = () ->
    check_status_server(server, server + test_pnc_online_url, update_status) for server in pnc_servers
    check_status_server(server, server + test_indy_online_url, update_status) for server in indy_servers
    check_status_server(server, server + test_da_online_url, update_status) for server in dependency_analysis_servers
    check_status_server(server, server, update_status) for server in jenkins_servers
    check_keycloak_server(server, update_status) for server in keycloak_servers
    check_repour_server(server, update_status) for server in repour_servers

  new CronJob("0 */5 * * * *", cron_check_status, null, true)

  # ============================================================================
  # pnc status command
  # ============================================================================
  robot.respond /(.*)pnc(.*)status(.*)/i, (res) ->
    check_status_server(server, server + test_pnc_online_url, reply_now("PNC", res)) for server in pnc_servers
    check_status_server(server, server + test_indy_online_url, reply_now("Indy", res)) for server in indy_servers
    check_status_server(server, server + test_da_online_url, reply_now("DA", res)) for server in dependency_analysis_servers
    check_status_server(server, server, reply_now("Jenkins", res)) for server in jenkins_servers
    check_keycloak_server(server, reply_now("Keycloak", res)) for server in keycloak_servers
    check_repour_server(server, reply_now("Repour", res)) for server in repour_servers


  robot.hear /^all[:,]+(.*)/i, (res) ->
    response = ''

    # build user list
    for own key, user of robot.brain.data.users
      # don't include the bot nick in all
      response += "#{user.name} " if user.room == res.envelope.room and user.name != robot.name

    response = response.trim() + ": " + res.match[1].trim() if response

    res.send response if response
