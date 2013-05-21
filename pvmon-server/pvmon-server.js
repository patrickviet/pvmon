#!/usr/local/bin/node


var rs = require('rolling_state.js');

/*
rs.insert_event({
	state: 'crit',
	time: (new Date()).getTime(),
	metric: 33,
	host: 'henri',
	service: 'bobby',
	rs_max_warn: 2,
	rs_max_crit: 2,
	rs_length: 5,
});

rs.insert_event({
	state: 'crit',
	time: (new Date()).getTime(),
	metric: 33,
	host: 'henri',
	service: 'jimmy/bobby',
	rs_max_warn: 2,
	rs_max_crit: 2,
	rs_length: 5,
});
*/

var streams = {
	'rolling_state': rs,
	'default': { 'insert_event': console.log }
};

var http = require('http');
var url = require('url');

http.createServer(function(req,res){

	if (req.method == 'POST') {
		var body = '';
		req.on('data', function(data) {
			body += data;
		});
		req.on('end', function() {
			
			// FIXME: add some more type checks
			var events = JSON.parse(body);
			events.forEach(function(ev) {
				if(!ev.hasOwnProperty('stream')) {
					ev.stream = 'default';
				}
				
				if(!streams.hasOwnProperty(ev.stream)) {
					ev.stream = 'default';
				}


				streams[ev.stream].insert_event(ev);

			});

			res.writeHead(200, {'Content-Type':'text/plain'});
			res.write("OK\n");
			res.end();
		});
	}


	//var my_path = url.parse(req.url).pathname;

	//if(url == '/insert_event') {

	//}

}).listen(8000);

