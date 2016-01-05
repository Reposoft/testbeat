
FROM ruby:2.2-slim

# using latest released version for now
RUN gem install testbeat

ENV spec=/spec/*_spec.rb

VOLUME /spec

# legacy env var name is NODE, confusing in microservices context, target service is now resolved from "specd" link
ENV NODE=specd

ENTRYPOINT [ "sh", "-c", "/usr/local/bundle/bin/rspec", "-c", "-f d", "$spec"]
