#!/bin/bash

TAR_SRC=/root/.local/share/node-subtensor/chains/nakamoto_mainnet/db/full
SNAPSHOT_TMP="tmp"

git -C /root/subtensorv2 pull origin master && cargo build --release --manifest-path /root/subtensorv2/Cargo.toml

currenthour=$(date +%H)
if [[ "$currenthour" == "00" ]]; then
	echo "[+] It's midnight, creating nightly snapshot"

	SNAPSHOT_FILENAME=snapshot_$(date +"%m-%d-%Y_%H")-00-nightly
	TAR_TARGET=/root/snapshots_nightly/$SNAPSHOT_FILENAME.tar.gz
	SNAPSHOT_DIR="snapshots_nightly"

	# Let's delete the oldest snapshot in here first.
	# we only need to maintain 2 days at a time.
	cd /root/$SNAPSHOT_DIR
	ls -1t | tail -n +3 | xargs rm
	cd ~
else
	echo "[+] Creating hourly snapshot"
	SNAPSHOT_FILENAME=snapshot_$(date +"%m-%d-%Y_%H")-00
	TAR_TARGET=/root/snapshots_hourly/$SNAPSHOT_FILENAME.tar.gz
	SNAPSHOT_DIR="snapshots_hourly"

	# Let's delete the oldest snapshot in here first.
	# we only need to maintain 10 hours at a time.
	cd /root/$SNAPSHOT_DIR
	ls -1t | tail -n +6 | xargs rm
	cd ~
fi

echo "[+] Removing previous docker images from previous build"
# Kill dangling docker images from previous builds
/usr/bin/docker system prune -a -f

echo "[+] Stopping Subtensor and starting database export"
# Stop subtensor and start the DB export
#/usr/local/bin/pm2 describe subtensor > /dev/null
RUNNING=`/usr/local/bin/pm2 pid subtensor`

# If subtensor is running, then start the export process.
# NOTE: Export won't happen if chain is down, because it would very likely be out of date.
if [ "${RUNNING}" -ne 0 ]; then
	
	echo "[+] Stopping subtensor PM2 job"
	# Stop subtensor chain so we can export the db
	/usr/local/bin/pm2 stop subtensor
	cd $TAR_SRC
	tar -zcvf $TAR_TARGET *
	
	# COPY TO TMP FOLDER
	cp $TAR_TARGET /root/$SNAPSHOT_TMP

	# Check if we tarred properly.
	if [[ $(tar ztvf $TAR_TARGET | grep "MANIFEST-*") ]]; then 

		# Add to ipfs
		#NEW_PIN=`ipfs add -Q -r /root/snapshots_hourly`
		#ipfs name publish /ipfs/$NEW_PIN
		cd ~		
		# Build docker image
		echo "[+] Building Docker image from directory ${SNAPSHOT_TMP} and snapshot file ${SNAPSHOT_FILENAME}"
		/usr/bin/docker build -t subtensor . --platform linux/x86_64 --build-arg SNAPSHOT_DIR=$SNAPSHOT_TMP --build-arg SNAPSHOT_FILE=$SNAPSHOT_FILENAME  -f /root/subtensor/Dockerfile --squash

		# Tag new image with latest
		echo "[+] Tagging new image with latest tag"
		/usr/bin/docker tag subtensor opentensorfdn/subtensor:latest
		/usr/bin/docker tag subtensor opentensorfdn/subtensor:$SNAPSHOT_FILENAME
	
		# now let's push this sum' bitch to dockerhub
		echo "[+] Pushing Docker image to DockerHub"
		/usr/bin/docker push opentensorfdn/subtensor:latest
		/usr/bin/docker push opentensorfdn/subtensor:$SNAPSHOT_FILENAME
	
		# Start the chain again
		echo "[+] Restarting Subtensor chain"
		/usr/local/bin/pm2 start subtensor --watch
	else
		echo "[-] Tar file is corrupt"
	fi
	cd ~  
	# Empty the snapshot tmp folder
	rm -rf $SNAPSHOT_TMP/*
else
	echo "[+] Subtensor is already stopped!"
fi
echo "\n"
