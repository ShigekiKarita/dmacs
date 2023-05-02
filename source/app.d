import core.stdc.ctype;
import core.stdc.errno;
import core.stdc.string;
import core.sys.posix.termios;
import core.sys.posix.unistd;
import std.file;
import std.getopt;
import std.logger;
import std.string;
import std.stdio;

Logger logger;

/// Returns: char array of string from errno.
const(char)[] errnoToString() {
  return fromStringz(strerror(errno));
}

/// Enable raw mode by turning off echo, canonical line-by-line stdin
/// (into byte-by-byte), and ctrl-* signals.
termios enableRawMode() {
  logger.log("enable raw mode");
  termios raw, orig;
  if (tcgetattr(STDIN_FILENO, &orig) == -1) {
    logger.fatal(errnoToString);
  }
  raw = orig;

  // Input flags.
  raw.c_iflag &= ~BRKINT; // Disable a break condition
  raw.c_iflag &= ~INPCK; // Disable parity check.
  raw.c_iflag &= ~ISTRIP; // Disable 8th bit input byte strip.
  raw.c_iflag &= ~ICRNL; // Disable ctrl-m for new line.
  raw.c_iflag &= ~IXON; // Disable ctrl-s/q which pauses/resumes transmissions.

  // Output flags.
  raw.c_oflag &= ~OPOST; // Disable postprocessing (adds \r before \n).

  // Misc flags.
  raw.c_cflag |= CS8; // For system compatibility with char size != 8 bits.

  // Local flags.
  raw.c_lflag &= ~ECHO; // hide chars typed.
  raw.c_lflag &= ~ICANON; // byte-by-byte stdin.
  raw.c_lflag &= ~IEXTEN; // disable ctrl-v/o.
  raw.c_lflag &= ~ISIG; // disable ctrl-c/z.

  // Input timeout for animation.
  raw.c_cc[VMIN] = 0;
  raw.c_cc[VTIME] = 1;

  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
    logger.fatal(errnoToString);
  }
  return orig;
}

/// Disable raw mode and revert the previous termios.
void disableRawMode(termios orig) {
  logger.log("disable raw mode");
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig) == -1) {
    logger.fatal(errnoToString);
  }
}

enum InitAppResult {
  success,
  fail,
  help,
}

// Returns true if this suceessfully initialized.
InitAppResult initApp(string[] args) {
  // Parse args.
  string logFile;
  LogLevel logLevel = LogLevel.all;
  GetoptResult result;
  try {
    result = std.getopt.getopt(
      args,
      "logFile", "file to write log", &logFile,
      "logLevel", "log level [all|trace|info|warning|error|critical|fatal|off]", &logLevel);
  }
  catch (GetOptException e) {
    auto _ = initApp([args[0], "--help"]);
    stderr.writeln("\nERROR: ", e.msg);
    return InitAppResult.fail;
  }

  // Print help messages.
  if (result.helpWanted) {
    defaultGetoptPrinter("Usage:", result.options);
    return InitAppResult.help;
  }

  // Initialize the logger.
  logger = new NullLogger;
  if (logFile) {
    logger = new FileLogger(logFile, logLevel);
  }
  logger.logf("logLevel: %s, logFile: %s", logLevel, logFile);
  return InitAppResult.success;
}

int main(string[] args) {
  final switch (initApp(args)) {
  case InitAppResult.success:
    break;
  case InitAppResult.fail:
    return 1;
  case InitAppResult.help:
    return 0;
  }

  termios orig = enableRawMode();
  logger.log("========= Start ==========");
  scope (exit) {
    disableRawMode(orig);
    logger.log("========= Exit ==========");
  }

  while (true) {
    char c;
    if (read(STDIN_FILENO, &c, 1) == -1 && errno != EAGAIN) {
      logger.fatal(errnoToString);
    }
    if (iscntrl(c)) {
      writef!"%d\r\n"(c);
    }
    else {
      writef!"%d ('%c')\r\n"(c, c);
    }
    if (c == 'q') {
      stderr.write("Good bye!\r\n");
      break;
    }
  }
  return 0;
}
