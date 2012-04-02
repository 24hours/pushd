event = require './event'
async = require 'async'
apns = require 'apn'
c2dm = require 'c2dm'
#mpns = require 'mpns'

class PushServiceAPNS
    constructor: (conf) ->
        @driver = new apns.Connection(conf)

    push: (device, subOptions, info, payload) ->
        note = new apns.Notification()
        note.device = new apns.Device(info.regid)
        if not (subOptions & event.OPTION_IGNORE_MESSAGE) and alert = payload.localizedMessage(info.lang) 
            note.alert = alert
        note.badge = badge if not isNaN(badge = parseInt(info.badge) + 1)
        note.sound = payload.sound
        note.payload = payload.data
        @driver.sendNotification note
        # On iOS we have to maintain the badge counter on the server
        device.incr 'badge'


class PushServiceC2DM
    constructor: (conf) ->
        conf.concurrency ?= 10
        conf.keepAlive = true
        @driver = new c2dm.C2DM(conf)
        @driver.login (err, token) =>
            if err then throw Error(err)
            [queuedTasks, @queue] = [@queue, async.queue(@_pushTask, conf.concurrency)]
            for task in queuedTasks
                @queue.push task
        # Queue into an array waiting for C2DM login to complete
        @queue = []

    push: (device, subOptions, info, payload) ->
        @queue.push
            device: device,
            subOptions: subOptions,
            info: info,
            payload: payload

    _pushTask: (task, done) ->
        note =
            registration_id: task.device.id
            collapse_key: task.payload.event.name
        if not (task.subOptions & event.OPTION_IGNORE_MESSAGE) and message = task.payload.localizedMessage(task.info.lang) 
            note['data.message'] = message
        note["data.#{key}"] = value for key, value of task.payload.data
        @driver.send note (err, msgid) ->
            done()
            if err in ['InvalidRegistration', 'NotRegistered']
                # Handle C2DM API feedback about no longer or invalid registrations
                task.device.delete()


class PushServiceMPNS
    constructor: (@conf) ->

    push: (device, subOptions, info, payload) ->
        # TO BE IMPLEMENTED


class PushServices
    services: {}

    addService: (protocol, service) ->
        @services[protocol] = service

    push: (device, subOptions, payload, cb) ->
        device.get (fields) =>
            if fields
                @services[fields.proto]?.push(device, subOptions, fields, payload)
            cb() if cb

exports.PushServices = PushServices

exports.getPushServices = (conf) ->
    services = new PushServices()
    services.addService('apns', new PushServiceAPNS(conf.apns)) if conf.apns
    services.addService('c2dm', new PushServiceC2DM(conf.c2dm)) if conf.c2dm
    services.addService('mpns', new PushServiceMPNS(conf.mpns)) if conf.mpns
    return services
