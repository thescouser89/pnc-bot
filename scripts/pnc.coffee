################################################################################
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
################################################################################

# Disable SSL check
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0"

config_file = "hubot-pnc.json"
test_pnc_online_url = "/pnc-rest/rest/users"
test_aprox_online_url = "/api/remote/central/xom/xom"


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


config = ''

running_builds_url = ''
build_configuration = ''
pnc_servers = []
aprox_servers = []
keycloak_servers = []
repour_servers = []

JSON_File.readFile(config_file, (err, obj) ->
  config = obj
  running_builds_url = "#{config.pnc_main_server}/pnc-rest/rest/running-build-records"
  build_configuration = "#{config.pnc_main_server}/pnc-rest/rest/build-configurations/"

  pnc_servers = config.pnc_servers
  aprox_servers = config.aprox_servers
  keycloak_servers = config.keycloak_servers
  repour_servers = config.repour_servers
)

# ==============================================================================
# Beginning of bot
# ==============================================================================
module.exports = (robot) ->

  # ============================================================================
  # Beginning of helper methods
  # ============================================================================
  send_build_configuration_name = (running_build, res) ->
    bc_id = running_build.buildConfigurationId
    running_build_id = running_build.id

    submit_date = new Date(running_build.submitTime)
    elapsed_submit_time = new Elapsed(submit_date, new Date())

    Rest.get(build_configuration + bc_id).on('complete', (result) ->
      res.send "#{result.content.name.irc.brown()}\##{running_build_id}" +
      " (submitted #{elapsed_submit_time.optimal.irc.white()} ago)"
    )

  check_if_server_online = (url, server_name, server_type, res) ->

    first_str = "#{server_type.irc.grey()} :: #{server_name} : "

    Rest.get(url).on('success', (result) ->
      res.send first_str + "Online".irc.green.bold()
    ).on('fail', (result) ->
      res.send first_str + "Online, but throwing errors".irc.yellow.bold.bgblack()
    ).on('error', (result) ->
      res.send first_str + "OFFLINE".irc.red.bold.bgwhite()
    )

  check_if_pnc_server_online = (pnc_server, res) ->
    check_if_server_online(pnc_server + test_pnc_online_url,
                           pnc_server, "PNC", res)

  check_if_aprox_server_online = (aprox_server, res) ->
    check_if_server_online(aprox_server + test_aprox_online_url,
                           aprox_server, "Aprox", res)

  # gonna do it custom for keycloak cause it's weird
  check_if_keycloak_server_online = (keycloak_server, res) ->

    request =
      data:
        grant_type: 'password'
        client_id: config.keycloak_config.client_id
        username: config.keycloak_config.username
        password: config.keycloak_config.password

    first_str = "Keycloak".irc.grey() + ":: #{keycloak_server} : "
    realm = config.keycloak_config.realm

    Rest.post("#{keycloak_server}/auth/realms/#{realm}/tokens/grants/access", request).on('success', (result) ->
        res.send first_str + "Online".irc.green.bold()
      ).on('fail', (result) ->
        res.send first_str + "Online, but throwing errors".irc.yellow.bold.bgblack()
      ).on('error', (result) ->
        res.send first_str + "OFFLINE".irc.red.bold.bgwhite()
      )

  # weirdly, we check if the repour server is online by seeing if it returns
  # 404. If not, then it's most probably down
  check_if_repour_server_online = (server_name, res) ->

    first_str = "Repour".grey() + " :: #{server_name} : "

    Rest.get(server_name).on('404', (result) ->
      res.send first_str + "Online".irc.green.bold()
    ).on('error', (result) ->
      res.send first_str + "OFFLINE".irc.red.bold.bgwhite()
    )
  # ============================================================================
  # End of helper methods
  # ============================================================================

  # ----------------------------------------------------------------------------

  # ============================================================================
  # Beginning of CronJob definition for monitoring
  # ============================================================================

  # server_status = {
  #   "server_name": "online",
  #   "server_name2": "offline"
  # }
  server_status = {}
  irc_status = (status) ->
    switch status
      when "Online" then status.irc.green.bold()
      when "Online, but throwing errors" then status.irc.yellow.bold.bgblack()
      when "OFFLINE" then status.irc.red.bold.bgwhite()

  message_channel = (server_url, status, old_status) ->

    opening_msg = ">>>".irc.bold.red()
    closing_msg = "<<<".irc.bold.red()
    message = "#{opening_msg} #{server_url} is now #{irc_status(status)}" +
              " (was previously #{irc_status(old_status)}) #{closing_msg}"

    robot.messageRoom config.pnc_monitoring_channel, message

  update_status = (server_url, status) ->
    if server_status[server_url]
      if server_status[server_url] != status
        robot.logger.info "#{server_url} is #{status}"
        message_channel server_url, status, server_status[server_url]
        server_status[server_url] = status
    else
      # first time the server is encountered, don't notify
      robot.logger.info "#{server_url} is #{status}"
      server_status[server_url] = status

  # TODO: rename those functions to something better later. it's getting confusing
  check_keycloak_server = (keycloak_server) ->

    request =
      data:
        grant_type: 'password'
        client_id: config.keycloak_config.client_id
        username: config.keycloak_config.username
        password: config.keycloak_config.password

    first_str = "Keycloak".irc.grey() + ": #{keycloak_server} :: "
    realm = config.keycloak_config.realm

    Rest.post("#{keycloak_server}/auth/realms/#{realm}/tokens/grants/access", request).on('success', (result) ->
      status = "Online"
      update_status(keycloak_server, status)
    ).on('fail', (result) ->
      status = "Online, but throwing errors"
      update_status(keycloak_server, status)
    ).on('error', (result) ->
      status = "OFFLINE"
      update_status(keycloak_server, status)
    )

  check_repour_server = (repour_server) ->
    status = ""
    Rest.get(repour_server).on('404', (result) ->
      status = "Online"
      update_status(repour_server, status)
    ).on('error', (result) ->
      status = "OFFLINE"
      update_status(repour_server, status)
    )


  check_status_server = (server_url, server_url_test) ->

    status = ""
    Rest.get(server_url_test).on('success', (result) ->
      status = "Online"
      update_status(server_url, status)
    ).on('fail', (result) ->
      status = "Online, but throwing errors"
      update_status(server_url, status)
    ).on('error', (result) ->
      status = "OFFLINE"
      update_status(server_url, status)
    )

  check_status = () ->
    check_status_server(server, server + test_pnc_online_url) for server in pnc_servers
    check_status_server(server, server + test_aprox_online_url) for server in aprox_servers
    check_keycloak_server(server) for server in keycloak_servers
    check_repour_server(server) for server in repour_servers

  new CronJob("0 */5 * * * *", check_status, null, true)
  # ============================================================================
  # End of Cronjob definition for monitoring
  # ============================================================================

  # ----------------------------------------------------------------------------


  # ============================================================================
  # Running builds command
  # ============================================================================
  robot.respond /(.*)running builds(.*)/i, (res) ->
    Rest.get(running_builds_url).on('success', (result) ->
      if result && result.content && result.content.length > 0
        send_build_configuration_name running_build, res for running_build in result.content
      else
        res.reply "No running builds on #{config.pnc_main_server.irc.gray()}"
    ).on('fail', (result) ->
      res.reply "#{config.pnc_main_server.irc.gray()} is throwing errors"
    ).on('error', (result) ->
      res.reply "#{config.pnc_main_server.irc.gray()} is " + "OFFLINE".irc.red.bold.bgwhite()
    )

  # ============================================================================
  # pnc status command
  # ============================================================================
  robot.respond /(.*)pnc(.*)status(.*)/i, (res) ->
    check_if_pnc_server_online pnc_server, res for pnc_server in pnc_servers
    check_if_aprox_server_online aprox_server, res for aprox_server in aprox_servers
    check_if_keycloak_server_online keycloak_server, res for keycloak_server in keycloak_servers
    check_if_repour_server_online repour_server, res for repour_server in repour_servers
