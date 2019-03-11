// Imports
let os;
let path;
let tracer;
if (typeof nodeRequire === 'undefined') {
    // We are in the main process
    /* eslint-disable global-require */
    os = require('os');
    path = require('path');
    tracer = require('tracer');
} else {
    // We are in the renderer process
    os = nodeRequire('os');
    path = nodeRequire('path');
    tracer = nodeRequire('tracer');
}

const isDev = process.mainModule.filename.indexOf('app.asar') === -1;

// Initialize the logger
// (this is called in both the main and renderer processes)
let logRoot;
if (isDev) {
    // In development, "__dirname" is:
    // "C:\Repositories\isaac-racing-client\src"
    // We want the log file in the root of the repository
    logRoot = path.join(__dirname, '..');
} else if (process.platform === 'darwin') {
    // We want the log file in the macOS user's "Logs" directory
    logRoot = path.join(os.homedir(), 'Library', 'Logs');
} else {
    // On a bundled Windows app, "__dirname" is:
    // "C:\Users\[Username]\AppData\Local\Programs\RacingPlus\resources\app.asar\src"
    // We want the log file in the "Programs" directory
    logRoot = path.join(__dirname, '..', '..', '..', '..');
}
const log = tracer.dailyfile({
    // Log file settings
    root: logRoot,
    logPathFormat: '{{root}}/Racing+ {{date}}.log',
    splitFormat: 'yyyy-mm-dd',
    maxLogFiles: 10,

    // Global tracer settings
    format: '{{timestamp}} <{{title}}> {{file}}:{{line}} - {{message}}',
    dateformat: 'ddd mmm dd HH:MM:ss Z',
    transport: (data) => {
        // Log errors to the JavaScript console in addition to the log file
        console.log(data.output);
    },
});

// Export it
module.exports = log;
