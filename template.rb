# template.rb
#
# Usage:
#   rails new my_app -m path/to/template.rb
#
# Or if you put this file on GitHub (e.g. raw URL), you can do:
#   rails new my_app -m https://raw.githubusercontent.com/<user>/<repo>/main/template.rb
#

# --------------------------------------------------------------------
# 1. Ask which DB adapter to use for PRODUCTION (dev/test = sqlite3)
# --------------------------------------------------------------------
db_choice = ask("Which database do you want for PRODUCTION? [postgresql, mysql, sqlite3]").downcase

valid_dbs = %w[postgresql mysql sqlite3]
unless valid_dbs.include?(db_choice)
  say "Invalid choice. Defaulting to sqlite3."
  db_choice = "sqlite3"
end

# --------------------------------------------------------------------
# 2. Update the Gemfile
#    - We'll add all 3 DB gems, but we'll control usage via config.
#      This way you can switch or test easily in the future.
# --------------------------------------------------------------------
insert_into_file 'Gemfile', after: /gem "rails".*\n/ do
  <<-RUBY

# For DB usage
gem 'pg', group: :production
gem 'mysql2', group: :production
gem 'sqlite3', '~> 1.4'
  RUBY
end

# Add Devise, Stripe, dotenv-rails
gem 'devise'
gem 'stripe'
gem 'dotenv-rails'

# --------------------------------------------------------------------
# 3. After bundle, run various generators & setup tasks
# --------------------------------------------------------------------
after_bundle do
  # ------------------------------------------------------------------
  # 3a. Setup Devise
  # ------------------------------------------------------------------
  generate "devise:install"
  # If you want a default User model:
  # generate "devise", "User"

  # ------------------------------------------------------------------
  # 3b. Setup Active Storage, Action Text
  # ------------------------------------------------------------------
  rails_command "active_storage:install"
  rails_command "action_text:install"

  # ------------------------------------------------------------------
  # 3c. Create app/services directory (Rails doesn’t create by default)
  # ------------------------------------------------------------------
  empty_directory "app/services"
  create_file "app/services/.keep"

  # ------------------------------------------------------------------
  # 3d. Configure database.yml for dev/test = sqlite3, prod = chosen DB
  # ------------------------------------------------------------------
  remove_file "config/database.yml"
  create_file "config/database.yml", <<-YML
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  <<: *default
  database: db/development.sqlite3

test:
  <<: *default
  database: db/test.sqlite3

production:
  adapter: #{db_choice == 'sqlite3' ? 'sqlite3' : db_choice}
  encoding: utf8
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  <%- if '#{db_choice}' == 'sqlite3' -%>
  database: db/production.sqlite3
  <%- elsif '#{db_choice}' == 'postgresql' -%>
  database: <%= ENV.fetch("POSTGRES_DB") { "#{app_name}_production" } %>
  username: <%= ENV.fetch("POSTGRES_USER") { "postgres" } %>
  password: <%= ENV.fetch("POSTGRES_PASSWORD") { "" } %>
  host: <%= ENV.fetch("POSTGRES_HOST") { "db" } %>
  <%- elsif '#{db_choice}' == 'mysql' -%>
  database: <%= ENV.fetch("MYSQL_DATABASE") { "#{app_name}_production" } %>
  username: <%= ENV.fetch("MYSQL_USER") { "root" } %>
  password: <%= ENV.fetch("MYSQL_PASSWORD") { "" } %>
  host: <%= ENV.fetch("MYSQL_HOST") { "db" } %>
  <%- end -%>

  YML

  # ------------------------------------------------------------------
  # 3e. Configure .env (example)
  # ------------------------------------------------------------------
  create_file ".env", <<-ENV
# Environment variables
RAILS_ENV=development
SECRET_KEY_BASE=#{SecureRandom.hex(64)}
MAILGUN_API_KEY=your_mailgun_api_key
MAILGUN_DOMAIN=your_mailgun_domain
STRIPE_PUBLIC_KEY=your_stripe_public_key
STRIPE_SECRET_KEY=your_stripe_secret_key
  ENV

  # ------------------------------------------------------------------
  # 3f. Configure production.rb for Action Mailer (Mailgun)
  # ------------------------------------------------------------------
  environment <<-RUBY, env: 'production'
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: 'smtp.mailgun.org',
      port: 587,
      domain: ENV.fetch("MAILGUN_DOMAIN") { 'example.com' },
      user_name: ENV.fetch("MAILGUN_SMTP_LOGIN") { '' },
      password: ENV.fetch("MAILGUN_SMTP_PASSWORD") { '' },
      authentication: 'plain',
      enable_starttls_auto: true
    }
  RUBY

  # ------------------------------------------------------------------
  # 3g. Add Bootstrap (with import maps) + keep Hotwire
  # ------------------------------------------------------------------
  # We'll just install bootstrap via import maps. 
  # For Rails 7, we can do something like:
  rails_command "importmap:install"
  append_to_file "config/importmap.rb" do
    <<~RUBY

      pin "bootstrap", to: "https://ga.jspm.io/npm:bootstrap@5.3.0/dist/js/bootstrap.esm.js"
    RUBY
  end

  # Include Bootstrap in application stylesheet (via asset pipeline or you could do more advanced setup).
  # For a minimal approach, we can just import the compiled CSS from a CDN in app/views/layouts/application.html.erb
  gsub_file "app/views/layouts/application.html.erb", /<\/head>/, <<-HTML
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" integrity="sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" crossorigin="anonymous">
</head>
  HTML

  # ------------------------------------------------------------------
  # 3h. Create Dockerfile & docker-compose.yml for production
  # ------------------------------------------------------------------
  create_file "Dockerfile", <<-DOCKER
# Use official Ruby image
FROM ruby:3.2

# Install dependencies
RUN apt-get update -qq && apt-get install -y nodejs

# Create app directory
WORKDIR /app

# Install gems
COPY Gemfile* ./
RUN bundle install

# Copy the rest of the app
COPY . .

# Precompile assets (optional for production)
# RUN bundle exec rails assets:precompile

# Expose port 3000
EXPOSE 3000

# Start the server (production environment)
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
  DOCKER

  create_file "docker-compose.yml", <<-YML
version: '3.8'
services:
  app:
    build: .
    env_file:
      - .env
    ports:
      - "3000:3000"
    depends_on:
      - db
    # If you need volumes for your code (in dev), you can add:
    # volumes:
    #   - .:/app

  db:
    image: #{db_choice == 'postgresql' ? 'postgres:15' : db_choice == 'mysql' ? 'mysql:8' : 'postgres:15'}
    environment:
      #{db_choice == 'postgresql' ? 'POSTGRES_DB: ${POSTGRES_DB}\n      POSTGRES_USER: ${POSTGRES_USER}\n      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}' : ''}
      #{db_choice == 'mysql' ? 'MYSQL_DATABASE: ${MYSQL_DATABASE}\n      MYSQL_USER: ${MYSQL_USER}\n      MYSQL_PASSWORD: ${MYSQL_PASSWORD}' : ''}
    ports:
      - "5432:5432"
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  db-data:
  YML

  # ------------------------------------------------------------------
  # 3i. Add a basic MIT license & README
  # ------------------------------------------------------------------
  create_file "LICENSE", <<-LICENSE
MIT License

Copyright (c) #{Time.now.year} #{app_name}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

(license continues) ...
  LICENSE

  create_file "README.md", <<-MD
# #{app_name}

Generated by [Rails application template](.)

## Quick Start

1. Copy \`.env\` to your needs and set the environment variables.
2. \`docker-compose build\`
3. \`docker-compose up -d\`
4. Go to http://localhost:3000

## License

[MIT](LICENSE)
  MD

  # ------------------------------------------------------------------
  # 3j. Final message
  # ------------------------------------------------------------------
  say "=================================================="
  say " Your app '#{app_name}' is ready!"
  say " 1. cd #{app_name}"
  say " 2. rails db:migrate (if you're running locally)"
  say " 3. rails s"
  say " Or use Docker: docker-compose up -d"
  say "=================================================="
end
