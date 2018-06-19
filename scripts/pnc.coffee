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
test_causeway_online_url = "/causeway/rest"
test_carto_online_url = "/api/admin/sources/aliases"

config = ''

username = ''
password = ''
registered = false

pnc_servers = []
indy_servers = []
jenkins_servers = []
keycloak_servers = []
dependency_analysis_servers = []
causeway_servers = []
cartographer_servers= []
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
  causeway_servers= config.causeway_servers
  cartographer_servers = config.cartographer_servers
  dependency_analysis_servers = config.dependency_analysis_servers
  repour_servers = config.repour_servers
  scrum_users = config.scrum_users
  username = config.username
  password = config.password
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

  register = () ->
    robot.logger.info "Registering bot..."
    robot.send {user: {name: 'UserServ'}}, "LOGIN " + username + ' ' + password
    robot.logger.info "Registering bot message sent..."


  # ============================================================================
  # Colorize the string based on the status
  # ============================================================================
  irc_colorize_status = (status) ->
    switch status
      when status_online then status.irc.green.bold()
      when status_online_errors then status.irc.yellow.bold.bgblack()
      when status_offline then status.irc.red.bold.bgwhite()

  mode_of_array = (array) ->
    item = ''
    mf = 1
    m = 0
    for i in [0...array.length]
      for j in [0...array.length]
        if array[i] == array[j]
          m++
          if mf < m
            mf = m
            item = array[i]

      m = 0

    if not item
      item = array[array.length - 1]

    item

  monitor = (server, env, status, handler) ->

      array = robot.brain.get(server + ":trend")

      if not array
          array = []

      # Adding data and maintaining structure part
      if array.length == 3
          array.shift()
          array.push(status)
      else
          array.push(status)

      robot.brain.set(server + ":trend", array)

      mode = mode_of_array(array)

      current_status = robot.brain.get(server + ":current")
      if current_status && current_status != mode
        handler server, env, mode

      robot.brain.set(server + ":current", mode)

  # ============================================================================
  # Print to the channel that a server has changed status
  #
  # Parameters:
  #   server_url: :string:
  #   new_status: :string:
  #   old_status: :string:
  # ============================================================================
  notify_status_change = (server_url, env, new_status) ->

    if env == "Devel"
      opening_msg = "[Devel]".irc.bold.green()

    if env == "Stage"
      opening_msg = "[Stage]".irc.bold.blue()

    if env == "Prod"
      opening_msg = "[Prod]".irc.bold.red()

    message = "#{opening_msg} #{server_url} is now #{irc_colorize_status(new_status)}"

    robot.messageRoom config.pnc_monitoring_channel, message

  # ============================================================================
  # Check if the Keycloak server is online
  #
  # Parameters:
  #   keycloak url: :string:
  #   handler: function accepting 2 parameters, first one is server url, second one is status
  # ============================================================================
  check_keycloak_server = (keycloak_url, env, handler) ->

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

      monitor(keycloak_url, env, status_online, handler)

    ).on('fail', (result) ->
      monitor(keycloak_url, env, status_online_errors, handler)
    ).on('error', (result) ->
      monitor(keycloak_url, env, status_offline, handler)
    )

  # ============================================================================
  # Check if the Repour server is online
  #
  # Parameters:
  #   repour url: :string:
  #   handler: function accepting 2 parameters, first one is server url, second one is status
  # ============================================================================
  check_repour_server = (repour_url, env, handler, retries = 2) ->
    Rest.get(repour_url).on('403', (result) ->
      robot.logger.info "#{repour_url} is online"
      monitor(repour_url, env, status_online, handler)
    ).on('503', (result) ->
      robot.logger.info "#{repour_url} is having issues"
      monitor(repour_url, env, status_online_errors, handler)
    ).on('error', (result) ->
      robot.logger.info "#{repour_url} is offline"
      monitor(repour_url, env, status_offline, handler)
    ).on('success', (result) ->
      robot.logger.info "#{repour_url} is online"
      monitor(repour_url, env, status_online, handler)
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
  check_status_server = (server_url, env, server_url_test, handler) ->

    Rest.get(server_url_test).on('success', (result) ->
      monitor(server_url, env, status_online, handler)
    ).on('fail', (result) ->
      monitor(server_url, env, status_online_errors, handler)
    ).on('error', (result) ->
      monitor(server_url, env, status_offline, handler)
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
  update_status = (server_url, env, status) ->
    robot.logger.info "#{server_url} is #{status}"
    notify_status_change server_url, env, status

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
    robot.messageRoom config.pnc_channel, users_str + ": " + message
    robot.messageRoom config.pnc_channel, config.scrum_extra_notes

  crontime_kanban = () ->
    users_str = config.prodcore_kanban_users.join(' ')
    message = "IT'S KANBAN TIME !!! IT'S KANBAN TIME !!! IT'S KANBAN TIME !!!".irc.rainbow.bold()
    robot.messageRoom config.prodcore_monitoring_channel, users_str + ": " + message
    robot.messageRoom config.prodcore_monitoring_channel, config.kanban_extra_notes

  new CronJob("0 58-59 14 * * 1-4", crontime, null, true, 'Europe/Prague')

  new CronJob("0 28-29 15 * * 2-4", crontime_kanban, null, true, 'Europe/Prague')

  # ============================================================================
  # *==* Update this function if you want to add a new server monitoring! *==*
  # Function invoked in the cron job
  # ============================================================================
  cron_check_status = () ->
    check_status_server(server["url"], server["env"], server["url"] + test_pnc_online_url, update_status) for server in pnc_servers
    check_status_server(server["url"], server["env"], server["url"] + test_indy_online_url, update_status) for server in indy_servers
    check_status_server(server["url"], server["env"], server["url"] + test_da_online_url, update_status) for server in dependency_analysis_servers
    check_status_server(server["url"], server["env"], server["url"], update_status) for server in jenkins_servers
    check_status_server(server["url"], server["env"], server["url"] + test_causeway_online_url, update_status) for server in causeway_servers
    check_status_server(server["url"], server["env"], server["url"] + test_carto_online_url, update_status) for server in cartographer_servers
    check_keycloak_server(server["url"], server["env"], update_status) for server in keycloak_servers
    check_repour_server(server["url"], server["env"], update_status) for server in repour_servers

  new CronJob("0 */3 * * * *", cron_check_status, null, true)

  # ============================================================================
  # pnc status command
  # ============================================================================
  robot.respond /(.*)pnc(.*)status(.*)/i, (res) ->
    res.send "Click the link to find the status: " + config.pncstatus_link


  robot.hear /^all[:,]+(.*)/i, (res) ->
    response = config.scrum_users.join(' ')

    response = response.trim() + ": " + res.match[1].trim() if response

    res.send response if response

  robot.enter (msg) ->
    username = msg.message.user.name
    room = msg.message.user.room
    if username == robot.name
      if registered isnt true
        register()
        registered = true