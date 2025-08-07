# Discourse AI Replier

A Discourse plugin that automatically generates AI replies to forum topics to increase community engagement. The plugin runs on a scheduled basis to select topics and generate contextual replies using external AI APIs.

## Installation

Add the plugin repository to your app.yml file:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/yourusername/discourse-ai-replier.git
```

Rebuild your Discourse container:

```bash
cd /var/discourse
./launcher rebuild app
```

## Usage

Once installed, the plugin automatically runs every hour to select topics and generate AI replies. The plugin uses a two-stage job system:

1. **Topic Selection Job**: Runs every hour to identify topics that need engagement
2. **Reply Generation Job**: Processes individual topics and generates AI replies

The plugin prioritizes:
- New topics with few replies (≤5 posts)
- Old topics that haven't been active for 3+ days but have good view counts (>50 views)

