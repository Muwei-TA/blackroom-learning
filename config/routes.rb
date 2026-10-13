# frozen_string_literal: true
BlackroomLearning::Engine.routes.draw do
  get '/' => 'learning#index'
  get '/data' => 'learning#index'
  post '/goals' => 'learning#create_goal'
  post '/checkins' => 'learning#create_checkin'
  post '/goals/:id/cancel' => 'learning#cancel'
end
