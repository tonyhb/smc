async     = require("async")

message = require("message")
misc    = require("misc")

conn = null

exports.setUp = (cb) ->
    conn = require("client_node").connect("http://localhost:5000")
    conn.on("connected", (proto) -> cb())

exports.tearDown = (cb) ->
    conn.on("close", cb)
    conn.close()

log = console.log

exports.test_account_management = (test) ->
    test.expect(24)
    email_address = "#{misc.uuid()}@salv.us"
    password = "#{misc.uuid()}"
    new_password = null
    async.series([
        (cb) ->
            conn.create_account(
                first_name    : ''
                last_name     : ''
                email_address : 'salvusmath-gmail.com'
                password      : 'qazqazqazqaz'
                agreed_to_terms : false
                timeout       : 1
                cb:(error, mesg) ->
                    test.equal(error, null)
                    log("Verify that account creation requires the terms of service to be agreed to")
                    test.equal(mesg.event,'account_creation_failed')
                    test.equal(mesg.reason.agreed_to_terms?, true)
                    log("Verify that first_name and last_name must both be nonempty.")
                    test.equal(mesg.reason.first_name?, true)
                    test.equal(mesg.reason.last_name?, true)
                    log("Verify that email address must be valid")
                    test.equal(mesg.reason.email_address?, true)
                    log("Verify that weak passwords are checked for")
                    test.equal(mesg.reason.password?, true)
                    cb()
            )
        
        (cb) ->
            log("Create a valid account")
            conn.create_account(
                first_name    : 'Salvus'
                last_name     : 'Math'
                email_address : email_address
                password      : password
                agreed_to_terms: true
                timeout       : 1
                cb:(error, mesg) ->
                    test.equal(error, undefined)
                    test.equal(mesg.event, 'signed_in')
                    test.equal(mesg.first_name, 'Salvus')
                    test.equal(mesg.last_name, 'Math')
                    test.equal(mesg.email_address, email_address)
                    test.equal(mesg.plan_name, 'Free')
                    cb()
            )

        # 
        (cb) ->
            log("Attempt to sign in to the account we just created -- first with the wrong password")
            conn.sign_in(
                email_address : email_address
                password      : password + 'wrong'
                timeout       : 1
                cb            : (error, mesg) ->
                    test.equal(mesg.event, "sign_in_failed")
                    cb()
            )
            
        
        (cb) ->
            log("Sign in to the account we just created -- now with the right password")
            conn.sign_in(
                email_address : email_address
                password      : password
                timeout       : 1
                cb            : (error, mesg) ->
                    test.equal(mesg.event, "signed_in")
                    test.equal(mesg.first_name, "Salvus")
                    test.equal(mesg.last_name, "Math")
                    test.equal(mesg.email_address, email_address)
                    test.equal(mesg.plan_name, "Free")
                    cb()
            )

        # Change password
        (cb) ->
            new_password = "#{misc.uuid()}"
            conn.change_password(
                email_address : email_address
                old_password  : password
                new_password  : new_password
                cb            : (error, mesg) ->
                    test.ok(not error) 
                    test.equal(mesg.event, 'changed_password')
                    test.equal(mesg.error, false)
                    cb()
            )

        # 
        (cb) ->
            log "Verify that the password is really changed"
            conn.sign_in(
                email_address : email_address
                password      : new_password
                timeout       : 1
                cb            : (error, mesg) ->
                    test.equal(mesg.event, "signed_in")
                    test.equal(mesg.email_address, email_address)
                    cb()
            )
            
    ], () -> test.done())

exports.test_user_feedback = (test) ->
    password = "#{misc.uuid()}"    
    test.expect(1)
    async.series([
        (cb) ->
            conn.create_account
                first_name    : 'Salvus'
                last_name     : 'Math'
                email_address : 'salvusmath2@gmail.com'
                password      : password
                agreed_to_terms: true
                timeout       : 1
                cb            : (error, results) -> console.log(error, results); cb()
        (cb) ->
            conn.sign_in
                email_address : 'salvusmath2@gmail.com'
                password      : password
                timeout       : 1
                cb            : (error, results) -> console.log(error, results); cb()
        (cb) -> 
            conn.report_feedback
                category : 'bug'
                description: "there is a bug"
                nps : 3
                cb : (err, results) -> console.log(err, results); cb()
        (cb) -> 
            conn.report_feedback
                category : 'idea'
                description: "there is a bug"
                nps : 3
                cb : (err, results) -> console.log(err, results); cb()
        (cb) ->
            conn.feedback
                cb: (err, results) ->
                    console.log(error, results);
                    test.equal(results.length, 2)
                    cb()
    ], () -> test.done())
    

exports.test_conn = (test) ->
    test.expect(9)
    async.series([
        (cb) ->
            uuid = conn.execute_code(
                code : '2+2'
                cb   : (mesg) ->
                    test.equal(mesg.stdout, '4\n')
                    test.equal(mesg.done, true)
                    test.equal(mesg.event, 'output')
                    test.equal(mesg.id, uuid); cb()
            )
        (cb) ->
            conn.on('ping', (tm) -> test.ok(tm<1); cb())
            conn.ping()
        # test the call mechanism for doing a simple ping/pong message back and forth
        (cb) ->
            conn.call(
                message : message.ping()
                cb      : (error, mesg) -> (test.equal(mesg.event,'pong'); cb())
            )
        # test the call mechanism for doing a simple ping/pong message back and forth -- but with a timeout that is *not* triggered
        (cb) ->
            conn.call(
                message : message.ping()
                timeout : 2  # 2 seconds
                cb      : (error, mesg) -> (test.equal(mesg.event,'pong'); cb())
            )
        # test sending a message that times out.
        (cb) ->
            conn.call(
                message : message.execute_code(code:'sleep(2)', allow_cache:false)
                timeout : 0.1
                cb      : (error, mesg) -> test.equal(error,true); test.equal(mesg.event,'error'); cb()
            )
    ], () -> test.done())

exports.test_session = (test) ->
    test.expect(8)
    s = null
    v = []
    async.series([
        # create a session that will time out after 5 seconds (just in case)
        (cb) -> s = conn.new_session(walltime:10); s.on("open", cb)
        # execute some code that will produce at least 2 output messages, and collect all messages
        (cb) -> s.execute_code(
                    code: "2+2;sys.stdout.flush();sleep(.5)",
                    cb: (mesg) ->
                        v.push(mesg)
                        if mesg.done
                            cb()
                )
        # make some checks on the messages
        (cb) ->
            test.equal(v[0].stdout, '4\n')
            test.equal(v[0].done, false)
            test.equal(v[1].stdout, '')
            test.equal(v[1].done, true)
            cb()
        # verify that the walltime method on the session is sane
        (cb) ->
            test.ok(s.walltime() >= .5)
            cb()
        # evaluate a silly expression without the Sage preparser
        (cb) ->
            s.execute_code(
                code:"2^3 + 1/3",
                cb:(mesg) -> test.equal(mesg.stdout,'1\n'); cb(),
                preparse:false
            )
        # start a computation going, then interrupt it and do something else
        (cb) ->
            s.execute_code(
                code:'print(1);sys.stdout.flush();sleep(10)', 
                cb: (mesg) ->
                    if not mesg.done
                        test.equal(mesg.stdout,'1\n')
                        s.interrupt()
                    else
                        test.equal(mesg.stderr.slice(0,5),'Error')
                        cb()
            )
    ],()->s.kill(); test.done())

