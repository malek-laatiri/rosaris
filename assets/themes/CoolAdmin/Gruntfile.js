/**
 * Grunt
 *
 * @see http://gruntjs.com/api/grunt to learn more about how grunt works
 * @since 1.0
 */

module.exports = function(grunt) {

	// Project configuration.
	grunt.initConfig({
		watch: {
			options: {
				livereload: true,
			},
			css: {
				files: ['css/*.css'],
				tasks: ['cssmin'],
				/*'autoprefixer', */
				options: {
					livereload: true
				},
			},
			livereload: {
				// Reload page when css files change.
				files: [
					'css/*.css'
				]
			},
		},

		cssmin: {
			options: {
				level: {
					2: {
						mergeIntoShorthands: false,
						roundingPrecision: false
					}
				}
			},
			target: {
				files: {
					'stylesheet.min.css': [
						'css/checkbox.css',
						'css/colors.css',
						'css/font.css',
						'css/icons.css',
						'css/radio.css',
						'css/stylesheet.css',
						'css/zresponsive.css',
						'css/rtl.css'
					],
					'stylesheet_wkhtmltopdf.min.css': [
						'css/colors.css',
						'css/font.css',
						'css/icons.css',
						'css/stylesheet.css',
						'css/rtl.css'
					]
				}
			}
		},
	});

	/**
	 * Load all plugins required
	 */
	grunt.loadNpmTasks('grunt-contrib-watch');
	grunt.loadNpmTasks('grunt-contrib-cssmin');

	// Default task(s).
	grunt.registerTask('default', ['watch']);
};
