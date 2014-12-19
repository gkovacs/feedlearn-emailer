#!/usr/bin/env lsc

root = exports ? this

require! {
  request
  async
  fs
  'next-time'
}

mongo = require 'mongodb'
{MongoClient} = mongo
mongourls = JSON.parse fs.readFileSync('.mongourls.json', 'utf-8')
# we can get these urls via "heroku config" command

mongourl = mongourls.mongohq

{sendgriduser, sendgridpassword} = JSON.parse fs.readFileSync('.sendgridlogin.json', 'utf-8')

sendgrid = require(\sendgrid) sendgriduser, sendgridpassword

get-mongo-db = (callback) ->
  MongoClient.connect mongourl, (err, db) ->
    if err
      console.log 'error getting mongodb'
    else
      callback db

get-logs-email-collection = (callback) ->
  get-mongo-db (db) ->
    callback db.collection('emaillogs'), db

wraphtml = (sometext) ->
  return """
  <html>
  <head></head>
  <body>
  #{sometext}
  </body>
  </html>
  """

mkemail = (userinfo) ->
  # {addr, weeknum} = userinfo
  addr = userinfo.addr
  username = userinfo.username
  weeknum = userinfo.weeknum
  timesent = userinfo.timesent
  console.log 'userinfo'
  console.log userinfo
  if [1,2,3].indexOf(weeknum) == -1
    console.log 'unknown weeknum ' + weeknum + ' for user ' + addr
    return null
  #linkurl = 'https://feedlearn.herokuapp.com/?email=true&emailuser=' + addr + '&timesent=' + timesent
  #imgurl = 'https://feedlearn.herokuapp.com/email-japanese.png?emailuser=' + addr + '&timesent=' + timesent
  linkurl1 = 'https://feedlearn.herokuapp.com/matching?vocab=japanese' + weeknum + '&type=posttest'
  linkurl2 = 'https://feedlearn.herokuapp.com/matching?vocab=japanese' + (weeknum+1) + '&type=pretest'
  emailtext = "Hi #{username}, thanks for participating in the FeedLearn study this week! To help us see what vocabulary you have learned this week and start studying the next set of words, please head to https://feedlearn.herokuapp.com/study1 and follow the instructions there to take the post-test for week #{weeknum} vocabulary, and the pre-test for week #{weeknum + 1}."
  if weeknum == 3
    emailtext = "Hi #{username}, thanks for participating in the FeedLearn study this week! To help us see what vocabulary you have learned this week and start studying the next set of words, please head to https://feedlearn.herokuapp.com/study1 and follow the instructions there to take the post-test for week #{weeknum} vocabulary." # post-study survey needed
  emailhtml = wraphtml "Hi #{username}, thanks for participating in the FeedLearn study this week! To help us see what vocabulary you have learned this week and start studying the next set of words, please head to <a href='https://feedlearn.herokuapp.com/study1'>https://feedlearn.herokuapp.com/study1</a> and follow the instructions there to take the post-test for week #{weeknum} vocabulary, and the pre-test for week #{weeknum + 1}."
  if weeknum == 3
    emailhtml = wraphtml "Hi #{username}, thanks for participating in the FeedLearn study this week! To help us see what vocabulary you have learned this week and start on the next week's material and start studying the next 50 words, please head to <a href='https://feedlearn.herokuapp.com/study1'>https://feedlearn.herokuapp.com/study1</a> and follow the instructions there to take the post-test for week #{weeknum} vocabulary."
  /*
  emailtext = '''
  Hi ''' + username +  '''', thanks for participating in the FeedLearn study! To help us see what vocabulary you have learned this week, please take the vocabulary post-test for week ''' + weeknum + ''' at: 
  ''' + linkurl1
  if weeknum != 3
    emailtext = '''
    Hi ''' + username + ''', thanks for participating in the FeedLearn study! To help us see what vocabulary you have learned this week, please take the vocabulary post-test for week ''' + weeknum + ''' at: 
    ''' + linkurl1 + ''' 
    Then, to help us see what vocabulary you already know from next week's vocabulary, please take the vocabulary pre-test for week ''' + (weeknum+1) + ''' at: 
    ''' + linkurl2
  emailhtml = '<html><head></head><body>Hi ' + username +  ', thanks for participating in the FeedLearn study this week! To help us see what vocabulary you have learned this week, please take the <a href="' + linkurl1 + '">vocabulary post-test for week ' + weeknum + '</a>.</body></html>'
  if weeknum != 3
    emailhtml = '<html><head></head><body>Hi ' + username +  ', thanks for participating in the FeedLearn study this week! To help us see what vocabulary you have learned this week, please take the <a href="' + linkurl1 + '">vocabulary post-test for week ' + weeknum + '</a>. Then, to help us see what vocabulary you already know from next week\'s vocabulary, please take the <a href="' + linkurl2 + '">vocabulary pre-test for week ' + (weeknum+1) + '</a></body></html>'
  */
  payload = {
    to: addr
    from: 'feedlearn@gmail.com'
    cc: 'feedlearn@gmail.com'
    subject: '[FeedLearn] Take Vocabulary Test for this week'
    text: emailtext
    html: emailhtml
  }
  if root.delayed and timesent > Date.now()
    payload.date = new Date(timesent)
  return payload

#addr = 'sanjay.kairam@gmail.com'
#addr = 'geza0kovacs@gmail.com'

sendemail = (userinfo, callback) ->
  email = new sendgrid.Email mkemail(userinfo)
  if root.delayed and userinfo.timesent > Date.now()
    email.set-send-at(Math.round(userinfo.timesent / 1000))
  sendgrid.send email, (err, result) ->
    console.log 'sending to:' + userinfo.addr
    console.log err
    console.log result
    callback(err, result)

send-exam-for-week-if-not-sent = (userinfo, callback) ->
  console.log 'send-exam-for-week-if-not-sent'
  have-sent-email-for-week userinfo, (res) ->
    console.log 'res is: ' + res
    if not res or root.resend[userinfo.username]?
      send-exam-for-week userinfo, ->
        callback(null, null) if callback?
    else
      callback(null, null) if callback?

send-exam-for-week = (userinfo, callback) ->
  console.log 'sent email for week to: ' + JSON.stringify(userinfo)
  if root.simulate? and root.simulate == true
    callback() if callback?
    return
  sendemail userinfo, ->
    add-sent-email-for-week userinfo, ->
      callback() if callback?

add-sent-email-for-week = (userinfo, callback) ->
  {username, addr, weeknum, timesent} = userinfo
  get-logs-email-collection (emails, db) ->
    emails.insert {type: 'emailexam', username, addr, weeknum, timesent, timequeued: root.timequeued}, (err, results) ->
      console.log err if err?
      callback() if callback?
      db.close()

have-sent-email-for-week = (userinfo, callback) ->
  {username, addr, weeknum} = userinfo
  get-logs-email-collection (emails, db) ->
    emails.find({type: 'emailexam', username: username, addr: addr, weeknum: weeknum}).toArray (err, results) ->
      console.log err if err?
      if not results? or results.length == 0
        callback(false)
      else
        callback(true)
      db.close()

get-userinfo = (callback) ->
  request.get 'http://feedlearn.herokuapp.com/gettesttimes', (err, results, body) ->
    output = []
    for {username,test,time} in JSON.parse body
      timesent = time
      addresses = root.username_to_email[username]
      if not addresses?
        console.log 'do not have email address for user: ' + username
        continue
      if typeof(addresses) == 'string'
        addresses = [addresses]
      weeknum = parseInt test.split('pretest').join('').split('posttest').join('')
      if [1,2,3].indexOf(weeknum) == -1
        console.log 'unknown weeknum: ' + weeknum + ' for user: ' + username
        continue
      if test.indexOf('pretest') != 0
        console.log 'unknown testtype:' + test + ' for user: ' + username
        continue
      if Date.now() > timesent
        console.log 'was supposed to send in the past at ' + (new Date(timesent).toString()) + ' for user: ' + username
        if not root.sendpast
          continue
      if timesent > Date.now() + 3600*1000*24
        console.log 'only need to send at ' + (new Date(timesent).toString()) + ' for user: ' + username
        continue
      for addr in addresses
        userinfo = {username, addr, weeknum, timesent}
        output.push userinfo
    callback(output)

root.username_to_email = JSON.parse fs.readFileSync('emails.json')

main = ->
  root.timequeued = Date.now()
  root.delayed = true
  root.sendpast = true
  root.simulate = true
  if process.argv.indexOf('send') != -1
    root.simulate = false
  root.resend = {
    #'Geza Kovacs'
  }
  get-userinfo (userinfo_list) ->
    console.log userinfo_list
    #userinfo_list = []
    #userinfo_list.push {"username": "Geza Kovacs", "addr": "feedlearn@gmail.com", weeknum: 1, timesent: Date.now()}
    async.mapSeries userinfo_list, send-exam-for-week-if-not-sent, (err, results) ->
      console.log 'mapSeries complete'
      console.log err
      console.log 'results:'
      for result in results
        console.log result
    # console.log userinfo_list


main()
# main()
