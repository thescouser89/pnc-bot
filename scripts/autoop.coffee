# Used to parse config file
JSON_File = require("jsonfile")

config_file = "hubot-pnc.json"

scrum_users = []
prodcore_kanban_users = []
op_channels = []

JSON_File.readFile(config_file, (err, obj) ->
  config = obj

  scrum_users = config.scrum_users
  prodcore_kanban_users = config.prodcore_kanban_users
  op_channels = config.op_channels
)

op_user = (robot, user, room) ->
    robot.adapter.command('MODE', room, '+o', user)

module.exports = (robot) ->
    robot.hear /^!op/i, (res) ->
        room = res.message.room
        op_user(robot, user, room, user) for user in scrum_users.concat prodcore_kanban_users

    robot.enter (msg) ->
      username = msg.message.user.name
      room = msg.message.user.room

      if username isnt robot.name && room in op_channels
        for user in scrum_users.concat prodcore_kanban_users
            if username.startsWith user
                op_user(robot, username, room)
                break
