FROM redmine:4.1.0

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
	unzip git imagemagick \
	build-essential pkg-config libssh2-1 libssh2-1-dev cmake libgpg-error-dev sudo ; # This row required for redmine-git-hosting \
	rm -rf /var/lib/apt/lists/*


RUN cd /usr/src/redmine/public/themes; \
    git clone https://bitbucket.org/dkuk/redmine_alex_skin.git; \
    chown -R redmine:redmine redmine_alex_skin; \
    git clone https://github.com/mrliptontea/PurpleMine2.git; \
    chown -R redmine:redmine PurpleMine2; \
    cd /usr/src/redmine/plugins;  \
    git clone https://github.com/toastedcrumpets/redmine_issue_dynamic_edit.git; \
    chown -R redmine:redmine redmine_issue_dynamic_edit; \
    mkdir /repos; \
    mkdir /localstore; \
    chown -R redmine:redmine /repos /localstore

VOLUME /repos
VOLUME /localstore

# Here we build all plugins that have been installed, this is time-consuming to do on image start (but migrations must be done then)
USER redmine
WORKDIR /usr/src/redmine
RUN bundle install --without development test

# Now we install git support, NOTE this cannot be done earlier due to issues on missing plugins.

USER root

RUN cd /usr/src/redmine/plugins; \
    git clone https://github.com/AlphaNodes/additionals.git; \
    chown -R redmine:redmine additionals; \
    git clone https://github.com/jbox-web/redmine_git_hosting.git; \
    chown -R redmine:redmine redmine_git_hosting

USER redmine

RUN bundle install --without development test

USER root

#Allow the redmine user to sudo to git, so the redmine git hosting
#plugin can direct access the gitolite repositories
RUN echo 'Defaults:redmine !requiretty\n\
redmine ALL=(git) NOPASSWD:ALL\n\
' > /etc/sudoers.d/redmine

# Make a dir for the redmine ssh config (known_hosts)
RUN chmod 440 /etc/sudoers.d/redmine; \
    mkdir /home/redmine/.ssh; \
    chown -R redmine:redmine /home/redmine/.ssh

USER root

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends  gitolite3 openssh-server; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; useradd -d /home/git -ms /bin/bash git

VOLUME /home/git

EXPOSE 22

USER root
WORKDIR /usr/src/redmine

# Install ruby for the git hooks
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ruby; \
    rm -rf /var/lib/apt/lists/*


## We add tini as sshd needs cleanup of its defunct processes
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc /tini.asc
RUN chmod +x /tini

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends  ruby-redcarpet; \
    mkdir /run/sshd; \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /

ENTRYPOINT ["/tini", "--"] 
CMD /docker-entrypoint.sh rails server -b 0.0.0.0

