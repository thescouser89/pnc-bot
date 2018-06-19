# Used to parse config file
JSON_File = require("jsonfile")

# this will make string be able to be formatted with IRC color
require("irc-colors").global()

# Cronjob
CronJob = require('cron').CronJob

config_file = "hubot-pnc.json"

config = ''


JSON_File.readFile(config_file, (err, obj) ->
  config = obj
)

module.exports = (robot) ->
  # ============================================================================
  # Simple cronjob to remind people it's scrum-time!
  # ============================================================================
  crontime_scrum = () ->
    users_str = config.scrum_users.join(' ')
    message = "IT'S SCRUM TIME !!!".irc.rainbow.bold()
    robot.messageRoom config.pnc_channel, users_str + ": " + message
    robot.messageRoom config.pnc_channel, config.scrum_extra_notes

  crontime_planning = () ->
    users_str = config.scrum_users.join(' ')
    message = "IT'S PLANNING TIME !!!".irc.rainbow.bold()
    robot.messageRoom config.pnc_channel, users_str + ": " + message
    robot.messageRoom config.pnc_channel, config.planning_extra_notes

  crontime_kanban = () ->
    users_str = config.prodcore_kanban_users.join(' ')
    message = "IT'S KANBAN TIME !!!".irc.rainbow.bold()
    robot.messageRoom config.prodcore_monitoring_channel, users_str + ": " + message
    robot.messageRoom config.prodcore_monitoring_channel, config.kanban_extra_notes

  crontime_prodtime = () ->
    users_str = config.prodcore_kanban_users.join(' ')
    message = "IT'S PRODCALL TIME !!!".irc.rainbow.bold()
    robot.messageRoom config.prodcore_monitoring_channel, users_str + ": " + message

  new CronJob("0 58-59 14 * * 1", crontime_planning, null, true, 'Europe/Prague')
  new CronJob("0 58-59 14 * * 2-4", crontime_scrum, null, true, 'Europe/Prague')

  new CronJob("0 28-29 15 * * 2-4", crontime_kanban, null, true, 'Europe/Prague')
  new CronJob("0 58 14 * * 5", crontime_prodtime, null, true, 'Europe/Prague')
