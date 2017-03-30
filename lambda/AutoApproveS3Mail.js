var AWS = require('aws-sdk');
var https = require('https');
var querystring = require('querystring');
exports.handler = function (event, context) {
        var s3 = new AWS.S3();
        
        if(event.RequestType == 'Delete') {                                    
            console.log("Delete Requested");
        }

        var s3params = {}; 
        s3params = {Bucket: event.Records[0].s3.bucket.name, Key: event.Records[0].s3.object.key };
        s3.getObject(s3params, function(err, data) {        
            if (err) { 
                console.log("Error Getting from S3");
                console.log(err);
            } else { 
                console.log('Successfully retreived data from S3');                                        
                var string = data.Body.toString();
                var indexpos = string.indexOf("https://certificates.amazon.com/approvals?");
                if(indexpos > 0){
                    string = string.substr(indexpos);
                    string = string.substr(0,string.indexOf("\n"));
                    console.log("URL: "+string);
                    
                    var responsecontent = "";   
                    
                    var req = https.request(string, function(res) {
                        res.setEncoding("utf8");
                        res.on("data", function (chunk) {
                            responsecontent += chunk;
                        });
                    
                        res.on("end", function () {
                            
                            var inputRegExp = /\<input.*?\/>/mg;
                            var nameRegExp = /name="([^\"]*)"/m;
                            var valueRegExp = /value="([^\"]*)"/m;
                            
                            var postObject = {
                                'utf8': '&#x2713',
                            };
                            
                            var o = responsecontent.toString().match(inputRegExp);
                            o.forEach(function (m) {
                               var name = m.match(nameRegExp)[1]; 
                               var value = m.match(valueRegExp)[1];
                               
                               postObject[name] = value;
                            });
                            
                            var postData = querystring.stringify(postObject);
                            
                            var options = {
                              hostname: 'certificates.amazon.com',
                              path: '/approvals',
                              method: 'POST',
                              headers: {
                                'Content-Type': 'application/x-www-form-urlencoded',
                                'Content-Length': Buffer.byteLength(postData)
                              }
                            };
                            console.log("Attempting to Submit Certificate Approval.");
                            var approvereq = https.request(options, (approveres) => {
                              console.log(`STATUS: ${approveres.statusCode}`);
                              console.log(`HEADERS: ${JSON.stringify(approveres.headers)}`);
                              approveres.setEncoding('utf8');
                              approveres.on('data', (chunk) => {
                                console.log(`BODY: ${chunk}`);
                              });
                              approveres.on('end', () => {
                                console.log('Certificate Approved');
                              });
                            });
                            
                            approvereq.on('error', (e) => {
                              console.log(`problem with request: ${e.message}`);
                            });
                            
                            // write data to request body
                            approvereq.write(postData);
                            approvereq.end();

                            
                        });
                    });
                    req.end();
                 }
                else{
                    console.log("URL Not Found in Mail");
                }
            }
        });
};