// pm2 start ecosystem.config.cjs && pm2 save
module.exports = {
	apps: [
		{
			name: 'familiahub-bot',
			script: 'index.ts',
			interpreter: 'node',
			node_args: '--env-file-if-exists=.env',
			cwd: __dirname,
			autorestart: true,
			restart_delay: 10000,
			max_restarts: 50,
			time: true,
		},
	],
}
