
# docker image for running CC test suite

FROM ubuntu

RUN apt-get -y install wget
RUN apt-get -y install librrd-dev
RUN apt-get -y install libreadline5
RUN apt-get -y install libyaml-0-2
RUN wget --progress=dot http://stackato-pkg.nas.activestate.com/repo-common/stackato-rubies_3.0.0-beta2_amd64.deb && dpkg -i stackato-rubies_3.0.0-beta2_amd64.deb
RUN apt-get -y install git

# kato requires these
RUN apt-get -y install libpq-dev
RUN apt-get -y install libsqlite3-dev

# mysql gem requires these
RUN apt-get -y install libmysqld-dev libmysqlclient-dev mysql-client

ENV PATH /opt/rubies/current/bin:$PATH
RUN echo "gem: --no-rdoc --no-ri" >> ~/.gemrc
RUN gem install bundler

RUN git clone -b cfv2 http://git-mirrors.activestate.com/github.com/ActiveState/cloud_controller_ng.git /cloud_controller_ng
RUN git clone -b cfv2 git://gitolite.activestate.com/vcap-common.git /common
RUN git clone -b master http://git-mirrors.activestate.com/github.com/ActiveState/steno-codec-text.git /steno-codec-text
RUN git clone -b cfv2 http://git-mirrors.activestate.com/github.com/ActiveState/kato.git /kato
RUN cd /kato && git pull && cd core && gem build stackato-kato.gemspec && gem install stackato-kato*.gem

# May be some gems installed that never get cleaned, but this will
# make the subsequent CMD runs faster
RUN cd /cloud_controller_ng && bundle install

CMD if [ -z $BRANCH ]; then BRANCH=cfv2; fi; cd /kato && git pull && cd core && gem build stackato-kato.gemspec && gem install stackato-kato*.gem && cd /cloud_controller_ng && git checkout $BRANCH && git submodule init && git submodule update && bundle install && RSPEC_FAIL_FAST=1 bundle exec rspec spec

