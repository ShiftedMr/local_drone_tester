Automating a simple drone server to be spun up when working on extensions

Prereq:
  Have docker running (docker desktop if on osx)

STEPS TO CONFIGURE
1: clone repo
2: If using defaults set up your /etc/hosts file to point at the hosts we'll be using
```
127.0.0.1 localgitea.local
127.0.0.1 localdrone.local
```
Note: if you want to use different hostnames change them above and use the same ones when asked by the launch script

3: From the cloned git repo 
bash launchScript.sh
Answer the question with best data; Git username should be whatever you're using locally to avoid issues

4: When everything starts up the default password for gitea is `supersecret`
5: Naviagate to http://localgitea.local
6: login with the credentials make sure it loads
7: In terminal in the cloned repo you can run (replacing your username in the uri)
`git remote add localgitea http://localgitea.local:3001/<gituser>/drone_test_world.git`
8: navigate to http://localdrone.local
9: click the welcome button (it'll redirect to gitea; click authorize)
10: fill out form with whatever info you want
11: activate the repo by navigating to it and clicking activate
12: in terminal do git push
13: a build should start :) 
