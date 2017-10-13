module.exports = (robot) ->
    robot.hear /^!factadd ([\w]+) (.*)/i, (res) ->

        if (res.match.length != 3)
            res.send "Error! Format is: !factadd <user> <fact>"
        else
            user = res.match[1].trim()
            fact = res.match[2].trim()
            existing_facts = robot.brain.get(user)

            if not existing_facts
                existing_facts = []

            existing_facts.push fact
            robot.brain.set(user, existing_facts)
            res.send user + " " + fact

    robot.hear /^!fact ([\w]+)/i, (res) ->
        res.send robot.brain.get(res.match[1].trim())
