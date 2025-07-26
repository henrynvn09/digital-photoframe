/* Config Sample
 *
 * For more information on how you can configure this file
 * see https://docs.magicmirror.builders/configuration/introduction.html
 * and https://docs.magicmirror.builders/modules/configuration.html
 *
 * You can use environment variables using a `config.js.template` file instead of `config.js`
 * which will be converted to `config.js` while starting. For more information
 * see https://docs.magicmirror.builders/configuration/introduction.html#enviromnent-variables
 */
let config = {
	address: "localhost",	// Address to listen on, can be:
	// - "localhost", "127.0.0.1", "::1" to listen on loopback interface
	// - another specific IPv4/6 to listen on a specific interface
	// - "0.0.0.0", "::" to listen on any interface
	// Default, when address config is left out or empty, is "localhost"
	port: 8080,
	basePath: "/",	// The URL path where MagicMirror² is hosted. If you are using a Reverse proxy
	// you must set the sub path here. basePath must end with a /
	ipWhitelist: ["127.0.0.1", "::ffff:127.0.0.1", "::1"],	// Set [] to allow all IP addresses
	// or add a specific IPv4 of 192.168.1.5 :
	// ["127.0.0.1", "::ffff:127.0.0.1", "::1", "::ffff:192.168.1.5"],
	// or IPv4 range of 192.168.3.0 --> 192.168.3.15 use CIDR format :
	// ["127.0.0.1", "::ffff:127.0.0.1", "::1", "::ffff:192.168.3.0/28"],

	useHttps: false,			// Support HTTPS or not, default "false" will use HTTP
	httpsPrivateKey: "",	// HTTPS private key path, only require when useHttps is true
	httpsCertificate: "",	// HTTPS Certificate path, only require when useHttps is true

	language: "en",
	locale: "en-US",   // this variable is provided as a consistent location
	// it is currently only used by 3rd party modules. no MagicMirror code uses this value
	// as we have no usage, we  have no constraints on what this field holds
	// see https://en.wikipedia.org/wiki/Locale_(computer_software) for the possibilities

	logLevel: ["INFO", "LOG", "WARN", "ERROR"], // Add "DEBUG" for even more logging
	timeFormat: 24,
	units: "metric",

	modules: [
		{
			module: "alert",
		},


		//		{
		//			module: "updatenotification",
		//			position: "top_bar"
		//		},
		{
			module: "clock",
			position: "top_left",
			config: {
				displaySeconds: false
			}
		},
		{
			module: "MMM-Worldclock",
			position: "top_left", // This can be any of the regions, best results in top_left or top_right regions.
			config: {
				timeFormat: "hh:mm A", // defined in moment.js format()
				style: "top", // predefined 4 styles; "top", "left","right","bottom"
				offsetTimezone: null, // Or you can set `Europe/Berlin` to get timegap difference from this timezone. `null` will be UTC timegap.
				clocks: [
					{
						title: "VIETNAM", // Too long title could cause ugly text align.
						timezone: "Asia/Ho_Chi_Minh", // When omitted, Localtime will be displayed. It might be not your purporse, I bet.
						flag: "vn",
					},
				]
			}
		},

		{
			module: "calendar",
			header: "CUỘC HẸN SẮP TỚI",
			position: "top_center",
			config: {
				calendars: [
					{
						fetchInterval: 60 * 60 * 1000,
						symbol: "lich trong nha",
						url: "<link to gcal>",
					}
				],
				showEnd: true,
				timeFormat: "absolute",
				urgency: 0,
			}
		},
		//		{
		//			module: "weather",
		//			position: "top_right",
		//			header: "Weather Forecast",
		//			config: {
		//				weatherProvider: "openmeteo",
		//				type: "forecast",
		//				lat: 33.8938101,
		//				lon: -118.0771511
		//			}
		//		},

		{
			module: "MMM-OpenWeatherMapForecast",
			header: "",
			position: "bottom_center",
			config: {
				apikey: "",
				latitude: "33.8992463",
				longitude: "-118.0689099",
				showSummary: false,
			},
		},


		{
			module: 'MMM-MicrosoftToDo',
			position: 'top_right',	// This can be any of the regions. Best results in left or right regions.
			header: 'Việc cần làm', // This is optional
			config: {
				oauth2ClientSecret: '',
				oauth2RefreshToken: '',
				oauth2ClientId: '',
				listName: 'Magic mirror', // optional parameter: if not specified displays tasks from default "Tasks" list, if specified will look for a task list with the specified name (exact spelling), don't specify if you want to make use of the 'includedLists' configuration property of the 'plannedTasks' configuration.
				// Optional parameter:  see Planned Tasks Configuration
				plannedTasks: {
					enable: false
				},
				showCheckbox: true, // optional parameter: default value is true and will show a checkbox before each todo list item
				showDueDate: true, // optional parameter: default value is false and will show the todo list items due date if it exists on the todo list item
				dateFormat: 'ddd MMM Do [ - ]', //optional parameter: uses moment date format and the default value is 'ddd MMM Do [ - ]'
				useRelativeDate: true, // optional parameter: default value is false and will display absolute due date, if set to false will show time in hours/days until item is due (midnight of due date)
				highlightTagColor: '#E3FF30', // optional parameter: highlight tags (#Tags) in the entry text. value can be a HTML color value
				hideIfEmpty: false, // optional parameter: default value is false and will show the module also when the todo list is empty
				maxWidth: 450, // optional parameter: max width in pixel, default value is 450
				itemLimit: 200, // optional parameter: limit on the number of items to show from the list, default value is 200
				orderBy: 'dueDate', // optional parameter: 'createdDate' - order results by creation date, 'dueDate' - order results by due date, 'importance' - order result by priority (e.g. starred), default value is unordered, ordering by title is not supported anymore in API version 1
				refreshSeconds: 60, // optional parameter: every how many seconds should the list be updated from the remote service, default value is 60
				fade: true, //optional parameter: default value is false. True will fade the list towards the bottom from the point set in the fadePoint parameter
				fadePoint: 0.5, //optional parameter: decimal value between 0 and 1 sets the point where the fade effect will start,
				colorDueDate: false // optional parameter: default value is false.  True will display colors for overdue (red), upcoming (orange), and future (green) dates
			}
		},

		{
			module: "MMM-ImmichSlideShow",
			position: "fullscreen_below",
			config: {
				immichConfigs: [
					{
						apiKey: '',
						url: "http://<your-nas-ip>:port",
						mode: 'search',
						imageInfo: ['date','geo','count'],
						query: {
							query: "building",
							takenBefore: "2025-01-25T00:00:00Z",
							size: 1000,
							type: "IMAGE",
							sortImagesBy: "created",
						},
						querySize: 1000,
						dateFormat: "DD-MM-YYYY dddd HH:mm",
						timeout: 30 *1000,
					}
				],
				backgroundSize: "contain",
				// transitionImages: true,
				// transitions: ["opacity"],
				showImageInfo: true,
				// imageInfoNoFileExt: true,
				// backgroundAnimaitonEnabled: true,
				// showBlurredImageForBlackBars: true,

			},
		},

		// {
		// 	module: 'MMM-RandomPhoto',
		// 	position: 'fullscreen_below',
		// 	config: {
		// 		imageRepository: "localdirectory",
		// 		repositoryConfig: {
		// 			path: "/mnt/synology",
		// 			recursive: true,
		// 			exclude: ["[#@]", ".*\\.(heic|HEIC|mov|MOV|mp4|MP4)$"],
		// 		},
		// 		imageFit: "contain",
		// 		showStatusIcon: false,
		// 		updateInterval: 10,
		// 		opacity: 1,
		// 		       showMetadata: true,
		//       metadataPosition: "bottom_left",
		//       metadataMode: "show"
		// 	}
		// },
		//
	]
};

/*************** DO NOT EDIT THE LINE BELOW ***************/
if (typeof module !== "undefined") { module.exports = config; }
