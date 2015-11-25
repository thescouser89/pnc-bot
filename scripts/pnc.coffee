Rest = require("restler")
Elapsed = require("elapsed")
IRC_Color = require("irc-colors")
JSON_File = require("jsonfile")

config_file = "hubot-pnc.json"

test_pnc_online_url = "/pnc-rest/rest/users"
test_aprox_online_url = "/api/remote/central/xom/xom"

config = ''

running_builds_url = ''
build_configuration = ''
pnc_servers = []
aprox_servers = []

JSON_File.readFile(config_file, (err, obj) ->
  config = obj
  running_builds_url = config.pnc_main_server + "/pnc-rest/rest/running-build-records"
  build_configuration = config.pnc_main_server + "/pnc-rest/rest/build-configurations/"

  pnc_servers = config.pnc_servers
  aprox_servers = config.aprox_servers
)

module.exports = (robot) ->

  send_build_configuration_name = (running_build, res) ->
    bc_id = running_build.buildConfigurationId
    running_build_id = running_build.id

    submit_date = new Date(running_build.submitTime)
    elapsed_submit_time = new Elapsed(submit_date, new Date())

    Rest.get(build_configuration + bc_id).on('complete', (result) ->
      res.send result.content.name + "#" + IRC_Color.blue.bold(running_build_id) +
               " (submitted " + IRC_Color.bold(elapsed_submit_time.optimal) + " ago)"

    )

  check_if_pnc_server_online = (pnc_server, res) ->
    Rest.get(pnc_server + test_pnc_online_url).on('success', (result) ->
      res.send IRC_Color.grey("PNC: ") + pnc_server + ": " + IRC_Color.green.bold("Online")
    ).on('fail', (result) ->
      res.send IRC_Color.grey("PNC: ") + pnc_server + ": " + IRC_Color.yellow.bold.bgblack("Online, but throwing errors")
    ).on('error', (result) ->
      res.send IRC_Color.grey("PNC: ") + pnc_server + ": " + IRC_Color.red.bold.bgwhite("OFFLINE")
    )

  check_if_aprox_server_online = (aprox_server, res) ->
    Rest.get(aprox_server + test_aprox_online_url).on('success', (result) ->
      res.send IRC_Color.grey("Aprox: ") + aprox_server + ": " + IRC_Color.green.bold("Online")
    ).on('fail', (result) ->
      res.send IRC_Color.grey("Aprox: ") + aprox_server + ": " + IRC_Color.yellow.bold.bgblack("Online, but throwing errors")
    ).on('error', (result) ->
      res.send IRC_Color.grey("Aprox: ") + aprox_server + ": " + IRC_Color.red.bold.bgwhite("OFFLINE")
    )

  robot.respond /(.*)running builds(.*)/i, (res) ->
    Rest.get(running_builds_url).on('complete', (result) ->
      send_build_configuration_name running_build, res for running_build in result.content
    )

  robot.respond /(.*)pnc(.*)status(.*)/i, (res) ->
    check_if_pnc_server_online pnc_server, res for pnc_server in pnc_servers
    check_if_aprox_server_online aprox_server, res for aprox_server in aprox_servers