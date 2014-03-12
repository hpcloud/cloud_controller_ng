# TODO:
# * connect to nats, postgres
# * connect to CF service gateways
# * connect to HM
# * proxy interface (nginx?)
# * how/when to run db:migrate?

FROM stackato/kato-core

ADD Dockerfile.sh /
ADD . /s/code/cloud_controller_ng/
WORKDIR /s/code/cloud_controller_ng/

RUN RUBYGEMS_MIRROR=http://asgems:3dnShTDN@gems.activestate.com \
  bash -ex /Dockerfile.sh

CMD ["bundle", "exec", "bin/cloud_controller", "-m"]
