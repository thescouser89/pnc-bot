random_item_in_list = (list) ->
    if list and list.length
        random_item = list[Math.floor(Math.random() * list.length)];
        return random_item
    else
        return null

clean_up_username = (username) ->
    while true
        if /-bot/.test(username)
            return username
        else if /-/.test(username)
            username = username.split("-")[0]
        else if /_/.test(username)
            username = username.split("_")[0]
        else if /\|/.test(username)
            username = username.split("|")[0]
        else
            return username

module.exports = (robot) ->
    robot.hear /^!factadd ([\w_|-]+) (.*)/i, (res) ->
        if (res.match.length != 3)
            res.send "Error! Format is: !factadd <user> <fact>"
        else
            user = clean_up_username(res.match[1].trim())
            fact = res.match[2].trim()
            existing_facts = robot.brain.get(user)

            if not existing_facts
                existing_facts = []

            existing_facts.push fact
            robot.brain.set(user, existing_facts)
            res.send user + " " + fact

    robot.hear /^!fact ([\w]+)/i, (res) ->
        user = clean_up_username(res.match[1].trim())
        facts = robot.brain.get(user)
        if facts
            random_fact = random_item_in_list(facts)
            res.send user + " " + random_fact if random_fact
        else
            res.send "No facts for user: " + user


    robot.enter (msg) ->
      username = msg.message.user.name
      room = msg.message.user.room
      if username isnt robot.name
          user = clean_up_username(username)
          facts = robot.brain.get(user)
          if facts
              random_fact = random_item_in_list(facts)
              robot.messageRoom room, user + " " + random_fact if random_fact
