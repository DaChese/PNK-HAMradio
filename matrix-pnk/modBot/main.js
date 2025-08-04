var fs = require('fs');
var http = require('http');
var request = require('request');
// var nude = require('nude');
// var uu = require('url-unshort');
// var phantom = require('phantom-render-stream');
// var render = phantom();
// var unshort = new uu();

var HackChat = require("./hackchat.js");
var chat = new HackChat();

//Data
var userStats = require("./userStats.json");
var config;
var directResponses;
var responses;
reload();

//Variables
var users = {};
var links = [];
var connections = {};
var afk = [];


//----------
//initialze
//----------

//Connect to the default channel
connections[config.botChannel] = chat.join(config.botChannel, config.botName, config.botPass);

//save the stats of the users preriodically
setInterval(function() {
    fs.writeFileSync("./userStats.json", JSON.stringify(userStats, undefined, 4));
}, 5 * 60 * 60 * 1000);
//ping for each connected channel
setInterval(function() {
    for (var session in connections) {
        connections[session].ping();
    }
}, 3 * 60 * 1000);


//---------
//events
//---------

chat.on("chat", function(session, nick, text, time, isAdmin, trip) {
    if (nick != config.botName && config.nickIgnore.indexOf(nick) == -1) {
        nick += " "
            //Check if he needs to send a direct reply
        if (text.toLowerCase().indexOf(config.botName.toLowerCase()) != -1) {
            for (var type in directResponses)
                if (text.indexOf(type) != -1)
                    session.sendMessage('@' + nick + " " + directResponses[type]);
        }

        //removes the user from the afk list
        if (afk.indexOf(nick) != -1)
        afk.splice(afk.indexOf(nick), 1);

        //merges the nick and trip name
        if (trip !== 'undefined')
            nick = nick + "#" + trip;

        //inspect the user
        if (config.ignore.indexOf(trip) == -1) {
            //push the image to the users' buffer
            logMesage(nick, text, time);

            var outPutMessage = '';
            //outPutMessage += linkCheck(session, text, nick) || '';
            outPutMessage += textCheck(nick) || '';
            if (outPutMessage !== ''){
                session.sendMessage(outPutMessage);
                return;
            }
        }

        //parse commands
        if (text[0] == config.commandPrefix) {
            parseCommand(session, nick, text, config.mods.indexOf(trip) != -1, isAdmin);
        } else {
          //Check if he needs to send a direct reply
          if (text.toLowerCase().indexOf(config.botName.toLowerCase()) != -1) {
              for (var type in directResponses)
                  if (text.indexOf(type) != -1)
                      session.sendMessage('@' + nick + " " + directResponses[type]);
          }

          //check if an AFK person was mentioned
          var atIndex = text.indexOf('@');
          if (atIndex != -1) {
            var targetNick = text.substr(atIndex + 1, text.indexOf(' ', atIndex) - 1);
            if (afk.indexOf(targetNick) != -1)
              session.sendMessage('@' + nick.split('#')[0] + ' ' + targetNick + ' is afk.');
          }
        }
    }
});

chat.on("joining", function(session) {
    console.log('joined ' + session.channel);
});

chat.on("info", function(session, text, time) {
    //check if someone got banned
    var words = text.split(" ");
    if (words[0] == "Banned") {
        for (user of getName(words[1]))
            userStats[user].banStatus++;
    }
});
chat.on("nicknameTaken", function() {
    // TODO: auto change nick
    console.log('nicknameTaken');
});

chat.on("ratelimit", function() {
    console.log("Rate limit");
});

chat.on("onlineRemove", function(session, nick) {
  if (afk.indexOf(nick) != -1)
    afk.splice(afk.indexOf(nick), 1);
})

//--------------
//Bot Functions
//--------------

//addes the lattest message to a buffer
function logMesage(nick, text, time) {
    //if user is not initialized yet, initialze it
    if (userStats[nick] && users[nick])
        users[nick].push({
            "time": time,
            "text": text
        }); //add the message to the users buffer
    else {
        if (!userStats[nick]) {
            //initialize the userstats data
            userStats[nick] = {
                "banCount": 0,
                "warningCount": 0
            };
        }

        //initialize the users buffer
        users[nick] = [{
            "time": time,
            "text": text
        }];
    }

    //Substract a message counter after 5 minutes for this user
    setTimeout(function() {
        users[nick].shift();
    }, 5 * 60 * 1000);
};

//Give a user a warning
function warnUser(nick, reason) {
    userStats[nick].warningCount++;
    console.log('User: ' + nick + ' ' + reason);
    users[nick] = [];
    setTimeout(function() {
        userStats[nick].warningCount--;
    }, 1 * 60 * 60 * 1000);
    return ("@" + nick + " $\\color{orange}{warning}$ #" + userStats[nick].warningCount + ": " + reason + "\n");
}

//return an arry with results from one nick name in the user stats
function getName(nick) {
    var matches = [];
    for (var user in userStats) {
        if (user.indexOf(nick) != -1)
            matches.push(user);
    }
    return matches;
}

//Join a channel
function join(channel) {
    if (channel[0] == '?')
      channel = channel.substr(1, channel.length);
    if (!connections[channel]) {
        connections[channel] = chat.join(channel, config.botName, config.botPass);
        console.log("joined " + channel);
    }
}

//Leave a channel
function leave(session) {
    if (session.channel == config.botChannel) {
        session.sendMessage("Can't leave this channel");
        return;
    }
    if (connections[session.channel]) {
        connections[session.channel].leave();
        console.log("left " + session.channel);
    }
}

function reload() {
    config = loadFile("./config.json");
    directResponses = loadFile('./directResponses.json');
    responses = loadFile("./responses.json");
}

//-----------
//spam detection functions
//-----------

//controll text
function textCheck(nick) {

    //could be that link check already passed a warning
    if (!users[nick])
        return;

    //Spam Region
    var maxMessages = 200; //Max amount of messages every 5 min
    var maxAvgtime = 1000; //Max difference that just baerly triggers the warning
    var maxSimilarityMultiLine = 0.75; //Max similarity between the first and third message
    var maxSimilaritySingleLine = 0.70; //Max similarity between the words in the text
    var maxLinecount = 8; //amount of lines a message can be max
    var maxWordLength = 200;
    var maxCharCount = 1500;

    var hasMulitpleMessages = users[nick].length > 2;

    var lastMessage = users[nick][users[nick].length - 1]; //last message send
    var secondlastMessage = hasMulitpleMessages ? users[nick][users[nick].length - 2] : ""; //second from last message send 
    var thirdLastMessage = hasMulitpleMessages ? users[nick][users[nick].length - 3] : ""; //third from last message send

    if (lastMessage) {

        //checks if a series of words is not longer then maxLinecount thresh hold
        if (lastMessage.text.split(/\r\n|\r|\n/).length > maxLinecount)
            return warnUser(nick, responses.longText); //long text

        //checks if there are not too many characters in a text
        if (charCount(lastMessage.text) > maxCharCount)
            return warnUser(nick, responses.longText); //long text 2

        //check if a single word is not too long
        if (longestWord(lastMessage.text).length > maxWordLength)
            return warnUser(nick, responses.longWord); //long word

        //check if a word is too repetitive within a text ( spam spam spam ) for example
        if (similar_inlineText(lastMessage.text, maxSimilaritySingleLine, maxSimilarityMultiLine))
            return warnUser(nick, responses.similarWords); // similar words

        //check if the user did not post too many message in the last n minutes
        if (users[nick].length > maxMessages)
            return warnUser(nick, responses.longTermSpeed); // long term speed count
        
        //check if this message is similar to the third from last message
        if ((similar_text(lastMessage.text, secondlastMessage.text) + similar_text(lastMessage.text, thirdLastMessage.text)) / 2 >= maxSimilarityMultiLine)
            return warnUser(nick, responses.similarMessage); // similar messages

        //check the speed between the last and third from last is not too fast
        if (lastMessage.time - thirdLastMessage.time < maxAvgtime)
            return warnUser(nick, responses.shortTermSpeed); // Short term speed count

        if (shortMessages(lastMessage.text, secondlastMessage.text, thirdLastMessage) && lastMessage.time - thirdLastMessage.time < maxAvgtime * 5)
            return warnUser(nick, responses.shortTermSpeedSpam); // Short term speed count
    }
}

//returns how similar 2 texts are
function similar_text(first, second) {
    if (first == second)
        return 1;

    firstArr = first.split(' ');
    for (var word in firstArr) {
        if (firstArr[word].indexOf('@') != -1)
            firstArr.splice(firstArr[word], 1);
        else
            firstArr[word] = firstArr[word].split('').sort().join('');
    }
    firstArr = firstArr.sort();
    secondArr = second.split(' ');
    for (word in secondArr) {
        if (secondArr[word].indexOf('@') != -1)
            secondArr.splice(secondArr[word], 1);
        else
            secondArr[word] = secondArr[word].split('').sort().join('');
    }
    secondArr = secondArr.sort();

    var similarityCounter = 0;
    for (word in first)
        if (first[word] == second[word])
            similarityCounter++;

    return similarityCounter / ((first.length + second.length) / 2.0);
}

//Check if all messages are too short
function shortMessages(first, second, third) {
    return (first.length <= 3 && second.length <= 3 && third.length <= 3)
}

//checks for repeating words within a text
function similar_inlineText(text, maxWordOccurence, maxSimilarity) {
    var checkedWords = [];
    var textArr = text.split(' ');
    if (textArr.length < 7)
        return false;
    for (var i = 0; i < textArr.length - 1; i++) {
        if (textArr[i] != "") {
            var wordCount = 1;
            if (checkedWords.indexOf(textArr[i]) == -1) {
                for (var k = i + 1; k < textArr.length; k++)
                    if (textArr[i] == textArr[k] || similar_text(textArr[i], textArr[k]) > maxSimilarity)
                        wordCount++;
                if (wordCount / textArr.length >= maxWordOccurence)
                    return true;
            }
            checkedWords.push(textArr[i]);
        }
    }
    return false;
}

//returns the longers word in a text
function longestWord(text) {
    var textArr = text.split(' ');
    var longest = textArr[0];
    for (var word of textArr)
        if (word != "" && word.length > longest.length)
            longest = word;
    return longest;
};

//returns the amount of characters a text is in length
function charCount(text) {
    return text.length;
}

//Controll links
function linkCheck(session, text, nick) {
    var urls = text.match(/(https?:\/\/)\S+?(?=[,.!?:)]?\s|$)/g); //returns an array with all links in the current message
    if (urls) {
        for (var url of urls) {
            if (links.indexOf(url) == -1) {
                //add the link to a list, to keep track of previously posted links
                links.push(url);
                setTimeout(function() {
                    links.shift();
                }, 10 * 60 * 1000); //Substract a link after 1 minutes

                //Preform a malicious link test, using the google API
                request('https://sb-ssl.google.com/safebrowsing/api/lookup?client=demo-app&key=' + config.gooleApiKey + '&appver=1.5.2&pver=3.1&url=' + url, function(error, response, body) {
                    if (!error && response.statusCode == 200)
                        session.sendMessage(warnUser(nick, "this link has been flagged as $\\color{red}{" + body + "}$"));
                });

                unshort.expand(url, function(err, urlnew) {
                    if (urlnew)
                        url = urlnew;

                    if (url.match(/(?:jpe?g|png)/g)) {
                        //preform nudity scan
                        scanFile(session, url, text);
                    } else {
                        //if the site was succesfully unshortend, render a preview, including the target domain
                        urlDomain = url.match(/^(?:https?:\/\/)?(?:[^@\n]+@)?(?:www\.)?([^:\/\n]+)/im)[1];
                        urlName = urlDomain.split('.')[0] + Math.floor(Math.random() * 1000);
                        previewSite(session, url, urlName, urlnew ? urlDomain : null);
                    }
                });
            } else
                session.sendMessage(warnUser(nick, "this link has been posted recently"));
        }
    }
}

//-----------
//file related Functions
//-----------

//Scan a file for nudity
var scanFile = function(session, url, message) {
    var filename = "temp.jpg";
    downloadFile(url, filename, true,
        function() {
            try {
                //nude.scan(filename, function(res) {
                    var fileName = url.split("/");
                    fileName = fileName[fileName.length - 1];
                    fs.rename(filename, config.path + fileName);
                    var message = "Nudity scan has been temp dissabled. ";
                    //if (message.toLowerCase().indexOf("nsfw") == -1 && res) {
                        //message += fileName + " flagged as possible [NSFW]\n";
                    //}
                    session.sendMessage(message + "Alternative link: " + config.domain + fileName + " available for 1 hour.");
                    setTimeout(function() {
                        try {
                            fs.unlink(config.path + fileName)
                        } catch (e) {
                            console.log(e + " error");
                        }
                    }, 1 * 60 * 60 * 1000); //remove file after 1 hour
                //});
            } catch (e) {
                console.log(e + "\nYour server might be out of memory (RAM)");
            }
        });
};

//download file
var downloadFile = function(uri, filename, validate, callback) {
    var valid = true;
    request.get(uri)
        .on('response', function(response) {
            if (response.statusCode != 200)
                valid = false;
            if (response.headers['content-type'].indexOf('image') == -1) // 'image/png'
                valid = false;
        })
        .pipe(fs.createWriteStream(filename))
        .on('close', function() {
            if (validate) {
                if (valid)
                    callback();
            } else callback();
        });
};

//render a preview of a Website
var previewSite = function(session, uri, name, domain) {
    render(uri, config.previewSettings)
        .on('error', function() {
            if (domain)
                session.sendMessage("Target domain is: " + domain + "\nPreview could not be generated");
            else
                session.sendMessage("Preview could not be generated");
        })
        .pipe(fs.createWriteStream(config.path + name + '.jpg'))
        .on('close', function() {
            if (domain)
                session.sendMessage("Target domain is: " + domain + "\nWebsite preview: " + config.domain + name + ".jpg");
            else
                session.sendMessage("Website preview: " + config.domain + name + ".jpg");
            setTimeout(function() {
                try {
                    fs.unlink(config.path + name + '.jpg');
                } catch (e) {
                    console.log(e);
                }
            }, 1 * 60 * 60 * 1000); //remove file after 1 hour
        });
}

//Async file loader
function loadFile(name) {
    return JSON.parse(fs.readFileSync(name).toString());
}

//---------
//commands
//---------

parseCommand = function(session, nick, message, isMod, isAdmin) {
    var args = message.split(" ");
    var command = String(args.splice(0, 1)).toLowerCase();
    command = command.substr(1, command.length);

    //normal commands
    switch (command) {
        //list stats for the current user
        case "stats":
            if (!isMod || !args || !isAdmin) {
                session.sendMessage("@" + nick + " ~ banCount: " + userStats[nick].banCount + " warningCount: " + userStats[nick].warningCount + "\n");
                return;
            }
            return;

            //Show the source of the bot
        case "source":
            session.sendMessage(config.botName + " is written by ToastyStoemp, the source code can be found here: https://github.com/ToastyStoemp/modBot ");
            return;
            
        case "afk":
            if (afk.indexOf(nick.split('#')[0]) == -1)
              afk.push(nick.split('#')[0]);
            break;
    }

    //Moderator commands
    if (isMod || isAdmin) {
        switch (command) {

            //lists all the stats for all users
            case "allstats":
                var newMessage = "";
                for (var name in userStats)
                    if (userStats[name].banCount !== 0 || userStats[name].warningCount !== 0)
                        newMessage += name + " ~ banCount: " + userStats[name].banCount + " warningCount: " + userStats[name].warningCount + "\n";
                session.sendMessage(newMessage);
                return;

                //saves the userstats
            case "save":
                fs.writeFile("./userStats.json", JSON.stringify(userStats), function() {});
                return;

            case "ignore":
                if (args[0] != "" && args[1] != "") {
                    if (args[0] == "trip") {
                        if (config.ignore.indexOf(args[1]) == -1) {
                            config.ignore.push(args[1]);
                            session.sendMessage(args[1] + " has been added to the trip ignore list.");
                            return fs.writeFile("./config.json", JSON.stringify(config), function() {});
                        }
                    } else if (args[0] == "nick") {
                        if (config.nickIgnore.indexOf(args[1]) == -1) {
                            config.nickIgnore.push(args[1]);
                            session.sendMessage(args[1] + " has been added to the nick ignore list.");
                            return fs.writeFile("./config.json", JSON.stringify(config), function() {});
                        }
                    }
                }
                return session.sendMessage("Usage: .ignore ['trip/nick'] [trip/nick]");

                //bans a user
            case "ban":
                if (args[0] != "") {
                    var target = args[0];
                    if (target[0] == '@')
                        target = target.substr(1, target.length);
                    if (config.banIgnore.indexOf(target) != -1)
                        return;
                    session.sendRaw({
                        cmd: "ban",
                        nick: target
                    });
                }
                return;

                //reloads some entities (check the reload function in main.js)
            case "reload":
                reload();
                return;

                //joins a specific channel
            case "join":
                if (args[0] != "" && args[0] != "?")
                    return join(args[0]);
                return session.sendMessage("Usage: .join [channel]");
                //connections[args[1]] = chat.join(text.split(" ")[1], config.botName, config.botPass);

                //leave specific channel
            case "leave":
                leave(session);
                return;
        }
    }
}
