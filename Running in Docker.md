# Running Lavaboom on your server

Lavaboom 2.0 codebase consists of multiple modules - a large API monolith,
mailer, frontend app and a few small services that add additional features.
This guide explains how to run the whole service on a server with Docker
installed. It assumes that there's a `172.16.0.0/24` network running and
the current server is `172.16.0.1`.

![Graph](http://i.imgur.com/tdr1YA3.png)

## RethinkDB

RethinkDB is used for all kinds of data storage in Lavaboom's services.

```bash
# fetch the image
docker pull anapsix/rethinkdb

# start the first server
docker run \
    -d \
    --name rethinkdb \
    -p 172.16.0.1:8080:8080 \
    -p 172.16.0.1:28015:28015 \
    -p 172.16.0.1:29015:29015 \
    rethinkdb

# on next servers
docker run \
    -d \
    --name rethinkdb \
    -p 172.16.0.x:8080:8080 \
    -p 172.16.0.x:28015:28015 \
    -p 172.16.0.x:29015:29015 \
    rethinkdb \
    --join 172.16.0.1:29015
```

### Redis

Redis is used for caching some data in the API.

```bash
# fetch the image
docker pull redis

# run it
docker run \
    -d \
    --name redis \
    -p 172.16.0.1:6379 \
    redis
```

### nsqd/nsqlookupd/nsqadmin

NSQ cluster is used for all kinds of messaging inside the Lavaboom service.
Running those commands sets up a minimal cluster with an admin service for
easy monitoring.

```bash
# fetch the image
docker pull nsqio/nsq

# run nsqlookupd
docker run \
    -d \
    --name nsqlookupd \
    -p 172.16.0.1:4160:4160 \
    -p 172.16.0.1:4161:4161 \
    nsqio/nsq \
    /nsqlookupd \
    --broadcast-address=172.16.0.1

# run nsqd
docker run \
    -d \
    --name nsqd \
    -p 172.16.0.1:4150:4150 \
    -p 172.16.0.1:4151:4151 \
    nsqio/nsq \
    /nsqd \
    --broadcast-address=172.16.0.1 \
    --lookupd-tcp-address=172.16.0.1:4160

# run nsqadmin
docker run \
    -d \
    -p 172.16.0.1:4171:4171 \
    --name nsqadmin \
    nsqio/nsq \
    /nsqadmin \
    --lookupd-http-address=172.16.0.1:4161
```

### SpamAssassin

Our SpamAssassin contains a basic set of rules that disable originating IP
checks.

```bash
# fetch spamd repo and build it
git clone https://github.com/lavab/spamd.git
cd spamd
docker build -t "lavab/spamd" .

# run spamd
docker run \
    -d \
    --name spamd \
    -p 172.16.0.1:783:783 \
    lavab/spamd
```

### Postfix

Postfix server is used for handling the outbound emails. It acts as a dumb
email proxy.

```bash
# build the image
git clone https://github.com/lavab/mailer.git
cd mailer/postfix
docker build -t "lavab/postfix" .

# run it
docker run \
    -d \
    -p 172.16.0.1:2525:25 \
    --restart always \
    --name postfix \
    lavab/postfix
```

## Web app

Web app is a nginx server that serves the Lavaboom Web AngularJS application.

```bash
# ensure that gulp is installed
npm install -g gulp

# fetch the image
git clone https://github.com/lavab/web.git
cd web

# build the lavab/web project
npm install
gulp production

# transform it into a docker image
docker build -t "lavab/web" .

# run it
docker run \
    -d \
    -p 127.0.0.1:10010:80 \
    --name web-master \
    lavab/web

# then proxy it through nginx/hipache
```

## Ritratt

Ritratt is a image proxy which uses a distributed LRU cache for storage.

```bash
# build the image
git clone https://github.com/lavab/ritratt.git
cd ritratt
docker build -t "lavab/ritratt" .

# run the image
docker run \
    -d \
    -p 127.0.0.1:13000:5000 \
    --restart always \
    --name ritratt \
    lavab/ritratt

# and then proxy it through nginx/hipache
```

## API

API is a monolith that handles most of the code interacting with the frontend.

```bash
# build the image
git clone https://github.com/lavab/api.git
cd api
docker build -t "lavab/api" .

# fetch the bloom filter for leaked passwords
mkdir -p /opt/lavab/api
curl -L https://github.com/lavab/api/releases/download/2.0.2/bloom.db > /opt/lavab/api/bloom.db

# run the api
docker run \
    -d \
    -p 127.0.0.1:10000:5000 \
    -v /opt/lavab/api:/ext \
    --name api-master \
    lavab/api \
    -redis_address=172.16.0.1:6379 \
    -redis_db=1 \
    -lookupd_address=172.16.0.1:4161 \
    -nsqd_address=172.16.0.1:4150 \
    -rethinkdb_address=172.16.0.1:28015 \
    -rethinkdb_db=prod \
    -api_host=api.lavaboom.com \
    -email_domain=lavaboom.com \
    -bloom_filter=/ext/bloom.db

# then proxy it through nginx/hipache
```

# Mailer

Mailer is one of the most important parts of Lavaboom. It consists of two
modules:
 - handler -  parses incoming emails, encrypts them if needed and writes
   them into database.
 - outbound - generates email bodies, signs them and passes them over to
   a dumb Postfix server that acts as a router for emails.

```bash
# build the image. note that we might already have the mailer cloned
git clone https://github.com/lavab/mailer.git
cd mailer
docker build -t "lavab/mailer" .

# generate a dkim key
mkdir -p /opt/lavab/keys
cd /opt/lavab/keys
opendkim-genkey -domain=lavaboom.com
cat default.txt # and use it in dns

# run it
docker run \
    -d \
    -p 25:25 \
    -v /opt/lavab/keys:/keys \
    --restart always \
    --name mailer \
    lavab/mailer \
    -rethinkdb_address=172.16.0.1:28015 \
    -rethinkdb_db=prod \
    -nsqd_address=172.16.0.1:4150 \
    -lookupd_address=172.16.0.1:4161 \
    -smtpd_address=172.16.0.1:2525 \
    -spamd_address=172.16.0.1:783 \
    -dkim_key=/keys/default.private \
    -dkim_selector=mailer \
    -hostname=lavaboom.com
```

# Lavabot

Lavabot is a small client application that sends onboarding emails to users
upon receiving a signal from the API.

```bash
# build the image
git clone https://github.com/lavab/lavabot.git
cd lavabot
docker build -t "lavab/lavabot" .

# prepare an account on the platform
# save its username and sha256 its password
# replace USERNAME1 and PASSWORD1
# usernames and passwords are comma-split lists

# receiver was replaced with a webhook, so right now
# enable_receiver must be false

# start the app
docker run \
    -d \
    --restart always \
    --name lavabot \
    lavab/lavabot \
    -rethinkdb_address=172.16.0.1:28015 \
    -nsqd_address=172.16.0.1:4150 \
    -lookupd_address=172.16.0.1:4161 \
    -usernames=USERNAME1 \
    -passwords=PASSWORD1 \
    -enable_receiver=false
```

# Invitation app and API

It's a small application used for handling registrations of users who didn't
specify their usernames or emails (for example indiegogo supporters).

```bash
# build the api
git clone https://github.com/lavab/invite-api.git
cd invite-api
docker build -t "lavab/invite-api" .

# build the app
git clone https://github.com/lavab/invite-web.git
cd invite-web
npm install -g gulp
npm install
gulp build
docker build -t "lavab/invite-web" .

# run the api
docker run \
    -d \
    -p 127.0.0.1:10021:8000 \
    --name invite-api \
    lavab/invite-api \
    -rethinkdb_address=172.16.0.1:28015

# run the app
docker run \
    -d \
    -p 127.0.0.1:10020:80 \
    --name invite-web \
    lavab/invite-web

# then proxy them using nginx/hipache
```

# Webhook runner

Webhook runner is a small application which runs webhooks upon receiving an
email to an account.

```bash
# build the image
git clone https://github.com/lavab/webhook.git
cd webhook
docker build -t "lavab/webhook" .

# start the runner
docker run \
        -d \
        --restart always \
        --name webhook \
        lavab/webhook \
        -rethinkdb_db=prod \
        -rethinkdb_address=172.16.0.1:28015 \
        -lookupd_addresss=172.16.0.1:4161
```

# Support webhook

Support integration forwards all incoming emails from an account to a
specified emails. We use it for Groove.

```bash
# build the image
git clone https://github.com/lavab/groove-webhook.git
cd groove-webhook
docker build -t "lavab/groove-webhook" .

# It requires the private key of the account you're binding
# to and the DKIM key of the mailer.

# start it
docker run \
    -d \
    -v /opt/lavab/keys:/keys \
    -p 172.16.0.1:1000:8000 \
    --restart always \
    --name groove-webhook \
    lavab/groove-webhook \
    -rethinkdb_database=prod \
    -rethinkdb_address=172.16.0.1:28015 \
    -private_key=/keys/test.key \
    -groove_address=test@inbox.groovehq.com \
    -forwarding_server=172.16.0.1:2525 \
    -dkim_key=/keys/default.private
```

After you run it, you have to add a new document to the `webhooks` table in
the database:

```javascript
{
    "address":       "http://172.16.0.1:1000/incoming",
    "date_created":  r.now(),
    "date_modified": r.now(),
    "id":            r.uuid(),
    "name":          "Groove integration",
    "owner":         "ID of your account",
    "target":        "ID of the account you want to bind to",
    "type":          "incoming"
}
```