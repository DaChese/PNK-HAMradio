# modBot
This bot is made possible due to the API provided by WebFreak001 ( https://github.com/WebFreak001 )
Made for Hack.Chat

#issues resolving
the canvas package needs cairo and node-gyp installed:
Cairo on Debian: $ sudo apt-get install libcairo2-dev libjpeg8-dev libpango1.0-dev libgif-dev build-essential g++
Node-gyp on Debian: $ npm install node-gyp -g

The phantom stream can cause issues:
Redownloading the precompiled phantomjs module fixes this issue, in node_modules, delete 'phantomjs-prebuilt'.
Then run $ npm install phantom-render-stream 
in the root folder of the project.
