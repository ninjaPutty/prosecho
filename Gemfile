source "https://rubygems.org"

gem "argon2", "~> 2.3"
gem "carnet", github: "menloparking/carnet", ref: "49ca60a54b057633315100d3f153ee73fbbec7e7"
gem "devise"
gem "lucide-rails"
gem "phlex-rails"
gem "pg", "~> 1.1"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rails", "8.1.3.1"
gem "solid_queue", "~> 1.3"
gem "tailwindcss-rails", "~> 4.0"
gem "turbo-rails"
gem "turnstile", github: "menloparking/turnstile", ref: "67ed37a064b9a861e7d78ee4e3874f38c0ae4535"
gem "tzinfo-data", platforms: %i[windows jruby]
gem "bootsnap", require: false

group :development, :test do
  gem "minitest-mock", require: false
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "standard", require: false
end

group :development do
  gem "kamal", "2.12.0", require: false
  gem "lookbook", "2.3.15"
  gem "lookbook_theme", github: "menloparking/lookbook_theme", tag: "v0.1.1"
  gem "web-console"
end
