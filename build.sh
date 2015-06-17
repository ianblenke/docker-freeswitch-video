#!/bin/bash

set -x -e

branch="master"
distribution="jessie"
outdir="/output"

# Functions
cleanup_git() { sudo -u source git reset --hard; sudo -u source git clean -f -x -d; }

aptly_republish() {
	sudo -u aptly aptly publish update -skip-signing ${distribution} || {
		sudo -u aptly aptly publish repo -distribution=${distribution} -architectures="source,all,$(dpkg --print-architecture)" -skip-signing freeswitch
	}
}

# Reset git
cd /usr/src/source/freeswitch
cleanup_git
sudo -u source git checkout $branch
sudo -u source git pull

longid="$(git rev-parse HEAD)"
shortid="$(git rev-parse --short HEAD)"
version="0.0~git$(date +%Y%m%d).${shortid}"
debversion="1:${version}-1"

# Only rebuild if the branch's HEAD wasn't already built
statusfile="/usr/src/last_build_${branch}"
touch $statusfile
if [[ "$(< ${statusfile})" == "${longid}" ]]; then
	echo -e "\nPackages of branch ${branch} already at ${shortid}"
	exit 0
fi

# Bootstrap debian directory
cd /usr/src/source/freeswitch/debian
sudo -u source ./bootstrap.sh -c ${distribution}

# Update Debian changelog
cd /usr/src/source/freeswitch
sudo -u source dch -D UNRELEASED -v "${debversion}" "NMU: Built by Docker container ${HOSTNAME}"

# Create sources
sudo -u source git-buildpackage -S -uc --git-compression-level=1

# Clean up git
cd /usr/src/source/freeswitch
cleanup_git

# Add sources to repository
sudo -u aptly aptly repo add freeswitch /usr/src/source/*.dsc
aptly_republish

# Clean up sources
find /usr/src/source/ -maxdepth 1 -type f -delete

# Install build dependencies
apt-get update
apt-get -y dist-upgrade
apt-get -y build-dep freeswitch
apt-get clean

# Clean up build area (necessary if the last build didn't succeed)
rm -rf /usr/src/build/*

# Build package from source in repository
cd /usr/src/build
sudo -u build apt-get --allow-unauthenticated source --build freeswitch

# Add binary packages to repository
sudo -u aptly aptly repo add freeswitch /usr/src/build/*.deb
aptly_republish

# Clean up build area
rm -rf /usr/src/build/*

# Update build status
echo $longid > $statusfile

# Copy/sync repo to output volume (if mounted)
[[ -e $outdir ]] && rsync -a --delete-after --no-owner /srv/aptly/public/ $outdir

set +x
echo -e "\nBUILD FINISHED\n"
if [[ -e $outdir ]]; then
	echo "Repository was synced to mountpoint ${outdir}"
else
	echo "You can copy the resulting repository from the conatiner using:"
	echo -e "\ndocker cp ${HOSTNAME}:/srv/aptly/public <destination>\n"
fi

