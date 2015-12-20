
FROM ruby:2.2-slim

# using latest released version for now
RUN gem install testbeat

ENV spec=/spec/*_spec.rb

# legacy name, confusing in microservices context
ENV NODE=service

VOLUME /spec

ENTRYPOINT ["/usr/local/bundle/bin/rspec", "-c", "-f d", $spec]
