# Used to parse config file
JSON_File = require("jsonfile")

config_file = "hubot-pnc.json"

username = ''
password = ''

registered = false

JSON_File.readFile(config_file, (err, obj) ->
  config = obj

  username = config.username
  password = config.password
)

register = (robot) ->

  robot.logger.info "Registering bot..."

  robot.send {user: {name: 'UserServ'}}, "LOGIN " + username + ' ' + password

  robot.logger.info "Registering bot message sent..."


module.exports = (robot) ->

  robot.enter (msg) ->

    username = msg.message.user.name
    room = msg.message.user.room

    if username == robot.name
      # only register once
      if registered isnt true
        register(robot)
        registered = true