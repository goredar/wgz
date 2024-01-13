# Wgz

Acme Zabbix tool

It's a console utility that prints actual zabbix triggers and could pipe them to
another app.

## Installation

Install ruby with appropriate pakage manager

```
[install ruby]
```

Install wgz gem

```
gem install wgz
```

Change username and password settings (use wga to install default template)

```
vim ./.l1.conf
```

Use it!

## Update

Don't foget to update regularly

```
gem update wgz
```

## Usage

Show unacknowledged triggers with priority higher or equal to Information
(default)

```
wgz
```

Filter by trigger name

```
wgz 'Low disk'
```

Filter by hostname

```
wgz -h fr2-sl-b84
```

Use linux tools to filter triggers

```
wgz | grep -v Puppet | wgz
```

Same without pipe (invert filtering)

```
wgz -v Puppet
```

Acknowledge selected triggers with given message

```
wgz -h host-1.acme.com --ack https://jira.acme.net/browse/JIRA-1
```

Reacknowledge selected triggers with previous message

```
wgz -h host-1.acme.net puppet --reack
```

See help for all avaliable options

```
wgz --help
```

## Run as a server (cache)

Running as caching server reduces processing time by fetching tirggers in
background. **!WARNING!** It's possible to receive stale data.

Add to your config file and change appropriately:

```
:wgz:
  :use_cache: true
  :socket: /tmp/wgz.sock
  :update_interval: 60
  :stale_threshold : 120
```

Run server in separate shell or add init unit to your init system

```
wgz --server
```

To force update server's cache use '-u' switch when getting triggers info

```
wgz -u
```

## Bugs, issues, feature requests and other suggestion

Feel free to post any kind of issue to GitLab. In case of any error try to run
with --debug option and post as many details as possible.
