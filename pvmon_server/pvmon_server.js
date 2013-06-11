#!/usr/local/bin/node

var url = require('url');

var urls = {
	'/insert_event': require('insert_event.js').process,
	'/get_state': require('get_state.js').get_state,
	'/get_host_list': require('get_state.js').get_host_list,
};


var http = require('http');

// for now it's unauthenticated ...

http.createServer(function(req,res){

	if (req.method == 'POST') {
		var body = '';
		req.on('data', function(data) {
			body += data;

			if (body.length > 1e6) { 
				// FLOOD ATTACK OR FAULTY CLIENT, NUKE REQUEST
				req.connection.destroy();
			}
		});
		req.on('end', function() {

			// parse url
			var myurl = url.parse(req.url);
			if (urls.hasOwnProperty(myurl.path)) {
				urls[myurl.path](req,res,body);
			} else {
				console.log('404: '+ myurl.path);
				console.log(body);
				res.writeHead(404, {'Content-Type':'text/plain'});
				res.write("404 Not found\n");
				res.end();
			}


		});
	} else {
		res.writeHead(403);
		res.write("403 Not this method\n");
		res.end();
	}

}).listen(8001,'127.0.0.1');

