#!/bin/sh

cd /usr/local/pvmon_server
./pvmon_server.js 2>&1 | logger -t pvmon_server
