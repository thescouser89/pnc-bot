
monitor = (robot, server, status, update_status) ->

    array = robot.brain.get(server)

    if not array
        array = []

    # Adding data and maintaining structure part
    if array.length == 3
        array.shift()
        array.push(status)
    else
        array.push(status)

    robot.brain.set(server, array)

    # Monitoring part: If the status has changed, and maintains that changed
    # status, send notification
    if array.length == 3
        if array[1] == array[2] && array[1] != array[0]
            update_status server, status

haha = (robot) ->

    robot.messageRoom "#dcheung-test", "hi dustin"