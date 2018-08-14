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

should_send_fact = (user, robot) ->
    last_time = robot.brain.get(user + "_last")
    robot.logger.info last_time
    if last_time != null
      time_now = new Date().getTime()

      time_elapsed_in_milliseconds = time_now - last_time
      time_elapsed_in_hours = time_elapsed_in_milliseconds / 3600000

      if time_elapsed_in_hours > 8
        robot.brain.set(user + "_last", time_now)
        return true
      else
        return false
    else
      robot.logger.info "else"
      robot.brain.set(user + "_last", new Date().getTime())
      return true



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

    robot.hear /^!quoteadd ([\w_|-]+) (.*)/i, (res) ->
        if (res.match.length != 3)
            res.send "Error! Format is: !quoteadd <user> <quote>"
        else
            user = clean_up_username(res.match[1].trim())
            quote = res.match[2].trim()
            existing_quotes = robot.brain.get(user + "_quotes")

            if not existing_quotes
                existing_quotes = []

            existing_quotes.push quote
            robot.brain.set(user + "_quotes", existing_quotes)
            res.send user + " once said, \"" + quote + "\""

    robot.hear /^!fact ([\w]+)/i, (res) ->
        user = clean_up_username(res.match[1].trim())
        facts = robot.brain.get(user)
        if facts
            random_fact = random_item_in_list(facts)
            res.send user + " " + random_fact if random_fact
        else
            res.send "No facts for user: " + user

    robot.hear /^!quote ([\w]+)/i, (res) ->
        user = clean_up_username(res.match[1].trim())
        quotes = robot.brain.get(user + "_quotes")
        if quotes
            random_quote = random_item_in_list(quotes)
            res.send user + " once said, \"" + random_quote + "\"" if random_quote
        else
            res.send "No quotes for user: " + user


    robot.enter (msg) ->
      username = msg.message.user.name
      room = msg.message.user.room

      if username isnt robot.name
          user = clean_up_username(username)

      if should_send_fact(user, robot)
        quote_or_list = []
        facts = robot.brain.get(user)
        quotes = robot.brain.get(user + "_quotes")

        if quotes && quotes.length > 1
            random_quote = random_item_in_list(quotes)
            quote_or_list.push user + " once said, \"" + random_quote + "\"" if random_quote

        # Only print fact when user enters if fact length greater than one
        # to avoid repetitive facts
        if facts && facts.length > 1
            random_fact = random_item_in_list(facts)
            quote_or_list.push user + " " + random_fact if random_fact

        if quote_or_list.length > 0
            robot.messageRoom room, random_item_in_list(quote_or_list)

