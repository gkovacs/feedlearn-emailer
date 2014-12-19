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

mkemail = (userinfo) ->
  {username, addr, dayselapsed} = userinfo
  timesent = root.timesent
  linkurl = 'https://feedlearn.herokuapp.com/?email=true&emailuser=' + addr + '&timesent=' + timesent
  imgurl = 'https://feedlearn.herokuapp.com/email-japanese.png?emailuser=' + addr + '&timesent=' + timesent
  payload = {
    to: addr
    from: 'feedlearn@gmail.com'
    cc: 'feedlearn@gmail.com'
    subject: '[FeedLearn] Daily Reminder: Study Vocabulary at FeedLearn'
    text: '''
  Your friends are studying vocabulary in Japanese at FeedLearn, go join them! 
  ''' + linkurl + ''' 
  ''' + username + ''', this is a daily reminder you are receiving because you are enrolled in the FeedLearn study, they will stop after a week (you are on day ''' + (dayselapsed + 1) + ''')
  '''
    html: '<html><head></head><body><a href="' + linkurl + '">Your friends are studying vocabulary in Japanese at FeedLearn, go join them!</a><br><a href="' + linkurl + '"><img src="' + imgurl + '"></img></a><br>' + username + ', this is a daily reminder you are receiving because you are enrolled in the FeedLearn study, they will stop after a week (you are on day ' + (dayselapsed + 1) + ')</body></html>'
  }
  if root.delayed
    payload.date = new Date(root.timesent)
  return payload

sendemail = (userinfo, callback) ->
  email = new sendgrid.Email mkemail(userinfo)
  if root.delayed
    email.set-send-at(Math.round(root.timesent / 1000))
  sendgrid.send email, (err, result) ->
    console.log 'sending to:' + userinfo.addr
    console.log err
    console.log result
    callback(err, result)

/*
async.mapSeries addresses, sendemail, (err, results) ->
  console.log 'mapSeries complete'
  console.log err
  for result in results
    console.log result
*/

send-daily-reminder-if-not-sent = (userinfo, callback) ->
  console.log 'send-daily-reminder-if-not-sent'
  have-sent-daily-reminder userinfo, (res) ->
    console.log 'res is: '+ res
    if not res or root.resend[userinfo.username]?
      send-daily-reminder userinfo, ->
        callback(null, null) if callback?
    else
      callback(null, null) if callback?

send-daily-reminder = (userinfo, callback) ->
  console.log 'sent daily reminder for week to: ' + JSON.stringify(userinfo)
  if root.simulate? and root.simulate == true
    callback() if callback?
    return
  sendemail userinfo, ->
    add-sent-daily-reminder userinfo, ->
      callback() if callback?

add-sent-daily-reminder = (userinfo, callback) ->
  console.log 'add-sent-daily-reminder'
  {username, addr, dayselapsed} = userinfo
  get-logs-email-collection (emails, db) ->
    emails.insert {type: 'dailyreminder', username, addr, dayselapsed, timesent: root.timesent, timequeued: root.timequeued}, (err, results) ->
      console.log err if err?
      callback() if callback?
      db.close()

have-sent-daily-reminder = (userinfo, callback) ->
  {username, addr, dayselapsed} = userinfo
  get-logs-email-collection (emails, db) ->
    emails.find({type: 'dailyreminder', username: username, addr: addr, dayselapsed: dayselapsed}).toArray (err, results) ->
      console.log err if err?
      if not results? or results.length == 0
        callback(false)
      else
        callback(true)
      db.close()

root.username_to_email = JSON.parse fs.readFileSync('emails.json')

get-userinfo-dailyemail = (callback) ->
  request.get 'http://feedlearn.herokuapp.com/getuserswhoneedemails', (err, results, body) ->
    output = []
    for {username,starttime,dayselapsed} in JSON.parse body
      addresses = root.username_to_email[username]
      if not addresses?
        console.log 'do not have email address for user: ' + username
        continue
      if typeof(addresses) == 'string'
        addresses = [addresses]
      for addr in addresses
        userinfo = {username, addr, dayselapsed}
        output.push userinfo
    callback output

main = ->
  root.timequeued = Date.now()
  root.timesent = Date.now()
  root.delayed = true
  if root.delayed
    root.timesent = +new Date(nextTime('10am'))
  root.simulate = true
  if process.argv.indexOf('send') != -1
    root.simulate = false
  root.resend = {
    #'Geza Kovacs'
  }
  get-userinfo-dailyemail (userinfo_list) ->
    #userinfo_list = []
    userinfo_list.push {"username":"Geza Kovacs","addr":"feedlearn@gmail.com ","dayselapsed": Math.floor((Date.now() - 1418806496234) / (1000*3600*24)) }
    console.log userinfo_list
    async.mapSeries userinfo_list, send-daily-reminder-if-not-sent, (err, results) ->
      console.log 'mapSeries complete'
      console.log err
      console.log 'results:'
      for result in results
        console.log result

main()


