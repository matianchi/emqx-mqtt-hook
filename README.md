
emqx_mqtt_hook
=====

EMQ broker plugin to catch broker hooks through mqtthook.<br>
[http://emqtt.io](http://emqtt.io)<br>

Setup
-----

##### In Makefile,

DEPS += emqx_mqtt_hook

dep_emqx_mqtt_hook = git https://github.com/matianchi/emqx-mqtt-hook master

##### In relx.config

{emqx_mqtt_hook_plugin, load}

##### emqx_mqtt_hook.conf
```
mqtt.hook.rule.client.connected.1     = {"action": "on_client_connected"}
mqtt.hook.rule.client.disconnected.1  = {"action": "on_client_disconnected"}
mqtt.hook.rule.client.subscribe.1     = {"action": "on_client_subscribe"}
mqtt.hook.rule.client.unsubscribe.1   = {"action": "on_client_unsubscribe"}
mqtt.hook.rule.session.created.1      = {"action": "on_session_created"}
mqtt.hook.rule.session.subscribed.1   = {"action": "on_session_subscribed"}
mqtt.hook.rule.session.unsubscribed.1 = {"action": "on_session_unsubscribed"}
mqtt.hook.rule.session.terminated.1   = {"action": "on_session_terminated"}
mqtt.hook.rule.message.publish.1      = {"action": "on_message_publish"}
mqtt.hook.rule.message.delivered.1    = {"action": "on_message_delivered"}
mqtt.hook.rule.message.acked.1        = {"action": "on_message_acked"}
```
##### subscribe
Subscribe topic 'dataflow' to receive messages.

License
-------

Apache License Version 2.0

Author
------

* matianchi

