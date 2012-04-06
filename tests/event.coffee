should = require 'should'
redis = require 'redis'
Subscriber = require('../lib/subscriber').Subscriber
Event = require('../lib/event').Event
PushServices = require('../lib/pushservices').PushServices


class PushServiceFake
    total: 0
    validateToken: (token) ->
        return token

    push: (subscriber, subOptions, info, payload) ->
        PushServiceFake::total++

createSubscriber = (redis, cb) ->
    info =
        proto: 'apns'
        token: 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660'
    Subscriber::create(redis, info, cb)

describe 'Event', ->
    @redis = null
    @event = null
    @subscriber = null

    beforeEach (done) =>
        @redis = redis.createClient()
        @redis.multi()
            .select(1) # use another db for testing
            .flushdb()
            .exec =>
                services = new PushServices()
                services.addService('apns', new PushServiceFake())
                @event = new Event(@redis, services, 'unit-test' + Math.round(Math.random() * 100000))
                done()

    afterEach (done) =>
        @event.delete =>
            if @subscriber?
                @subscriber.delete =>
                    @redis.keys '*', (err, keys) =>
                        @redis.quit()
                        keys.should.be.empty
                        @subscriber = null
                        done()
            else
                @redis.keys '*', (err, keys) =>
                    keys.should.be.empty
                    done()

    describe 'publish()', =>
        it 'should not push anything if no subscribers', (done) =>
            PushServiceFake::total = 0
            @event.publish {msg: 'test'}, (total) =>
                PushServiceFake::total.should.equal 0
                total.should.equal 0
                done()

        it 'should push to one subscriber', (done) =>
            createSubscriber @redis, (@subscriber) =>
                @subscriber.addSubscription @event, 0, (added) =>
                    added.should.be.true
                    PushServiceFake::total.should.equal 0
                    @event.publish {msg: 'test'}, (total) =>
                        PushServiceFake::total.should.equal 1
                        total.should.equal 1
                        done()

    describe 'stats', =>
        it 'should increment increment total field on new subscription', (done) =>
            @event.publish {msg: 'test'}, =>
                @event.info (info) =>
                    should.not.exist(info)
                    createSubscriber @redis, (@subscriber) =>
                        @subscriber.addSubscription @event, 0, (added) =>
                            added.should.be.true
                            @event.publish {msg: 'test'}, =>
                                @event.info (info) =>
                                    should.exist(info)
                                    info?.total.should.equal 1
                                    done()

    describe 'delete()', =>
        it 'should unsubscribe subscribers', (done) =>
            createSubscriber @redis, (@subscriber) =>
                @subscriber.addSubscription @event, 0, (added) =>
                    added.should.be.true
                    @event.delete =>
                        @subscriber.getSubscriptions (subcriptions) =>
                            subcriptions.should.be.empty
                            done()
