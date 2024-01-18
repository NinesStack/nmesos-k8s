FROM ruby:3.2-alpine3.18

WORKDIR /deploy

ADD nmesos-k8s Gemfile Gemfile.lock entrypoint.sh .

RUN apk update \
  && apk add --no-cache build-base ruby-dev aws-cli bash \
  && apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community kubectl \
  && bundle install \ 
  && apk del build-base ruby-dev \
  && rm -rf /var/cache/apk/*

ENTRYPOINT ["/deploy/entrypoint.sh"] 
