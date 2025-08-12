my magicmirror config for a digital photoframe using a 27-in monitor. It sync google calendar, microsoft todo, and shows images from immich.

<img src="https://github.com/user-attachments/assets/06a367d3-47bb-4454-9f28-7fd8bd04826f" height="500">


# Config

I'm running server MM on NAS and Rasperry Pi as a client

## config Rasperry Pi Client
for client, after running [auto script](https://docs.magicmirror.builders/getting-started/installation.html#automatic-installation-scripts), we need to edit config file from `pm2 show mm` such as [my config](mm.sh)

```sh
node clientonly --address 192.168.1.5 --port 8080
```

Then adding those script to `crontab`
```sh
## Weekends: ON at 8:00 AM, OFF at 8:45 PM
0 8 * * 6,0 /bin/bash /home/pi/Code/magicmirror-config/client/turn_on_magic_mirror.sh >> /home/pi/magicmirror_start.log 2>&1
45 20 * * 6,0  /bin/bash /home/pi/Code/magicmirror-config/client/turn_off_magic_mirror.sh >> /home/pi/magicmirror_stop.log  2>&1
## Weekdays: ON at 4:00 PM, OFF at 8:45 PM
0 16 * * 1-5 /bin/bash /home/pi/Code/magicmirror-config/client/turn_on_magic_mirror.sh >> /home/pi/magicmirror_start.log 2>&1
45 20 * * 1-5 /bin/bash /home/pi/Code/magicmirror-config/client/turn_off_magic_mirror.sh >> /home/pi/magicmirror_stop.log  2>&1
```

# required modules
default
MMM-MicrosoftToDo
MMM-Worldclock
MMM-ImmichSlideShow 
**henrynvn09/MMM-OpenWeatherMapForecast**

# useful command, resources
running mm on NAS
```sh
docker run -d --name magicmirror --publish 8036:8080 --restart unless-stopped -e TZ=America/Los_Angeles --volume /volume1/docker/magicmirror/config:/opt/magic_mirror/config --volume /volume1/docker/magicmirror/modules:/opt/magic_mirror/modules --volume /volume1/docker/magicmirror/css:/opt/magic_mirror/css karsten13/magicmirror:latest
```
Note that all modules inside docker must be ran `npm i` within the docker environment
