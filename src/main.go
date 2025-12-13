package main

import (
	"fmt"
	"log"
	"log/slog"
	"mime"
	"net/http"
	"os"
	"runtime/debug"

	charmlog "github.com/charmbracelet/log"
	"github.com/joho/godotenv"
	"code.msyke.dev/mSyke/sourdough-go-web-k8s/common"
	slogmulti "github.com/samber/slog-multi"
	slogslack "github.com/samber/slog-slack/v2"
)

func main() {
	err := godotenv.Load(".env")
	if err != nil {
		log.Printf("No .env file found. No environment variables loaded from file: %s", err)
	}

	var loggerWebhookUrl = os.Getenv(common.SOURDOUGH_GO_SLACK_WEBHOOK_URL)
	const channel = "alerts"
	logger := slog.New(slogmulti.Fanout(
		slogslack.Option{Level: slog.LevelWarn, WebhookURL: loggerWebhookUrl, Channel: channel, AddSource: true}.NewSlackHandler(),
		charmlog.NewWithOptions(os.Stdout, charmlog.Options{ReportCaller: true, ReportTimestamp: true, Level: charmlog.DebugLevel}),
	))

	hostname, err := os.Hostname()
	if err != nil {
		logger.Error("Error getting hostname", "error", err)
		panic(err)
	}

	logger = logger.
		With("host", hostname)

	appEnv := os.Getenv("APP_ENV")
	if appEnv != "local" {
		logger.Warn(fmt.Sprintf("Starting %s in prod mode 5001...", common.APP_NAME))
	} else {
		logger.Info(fmt.Sprintf("Starting %s in local mode on port 5001...", common.APP_NAME))
	}

	fixMimeTypes()

	// http.HandleFunc("/", WithErrorHandling(handlers.LandingPageHandler(db, logger), logger))

	failOnError(http.ListenAndServe(":5001", nil), "Failed to start server", logger)
}

func failOnError(err error, msg string, logger *slog.Logger) {
	if err != nil {
		logger.Error(msg, "error", err)
		log.Panicf("%s: %s", msg, err)
	}
}

func WithErrorHandling(handlerFunc func(http.ResponseWriter, *http.Request), logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				logger.Error("An unknown error occured", "err", err, "path", r.URL, "stackTrace", string(debug.Stack()))
				logger.Error("An unknown error occured", "err", err, "path", r.URL)
				http.Error(w, "Internal server error", http.StatusInternalServerError)
			}
		}()

		handlerFunc(w, r)
	}
}

func fixMimeTypes() {
	err1 := mime.AddExtensionType(".js", "text/javascript")
	if err1 != nil {
		log.Printf("Error in mime js %s", err1.Error())
	}

	err2 := mime.AddExtensionType(".css", "text/css")
	if err2 != nil {
		log.Printf("Error in mime js %s", err2.Error())
	}
}
