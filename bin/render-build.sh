#!/usr/bin/env bash
set -o errexit

bundle install
yarn install
bundle exec rails vite:build_all
