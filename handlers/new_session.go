package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"path"
	"strings"

	"github.com/play-with-docker/play-with-docker/config"
	"github.com/play-with-docker/play-with-docker/provisioner"
)

type NewSessionResponse struct {
	SessionId string `json:"session_id"`
	Hostname  string `json:"hostname"`
}

func NewSession(rw http.ResponseWriter, req *http.Request) {
	req.ParseForm()

	userId := ""
	if len(config.Providers) > 0 {
		cookie, err := ReadCookie(req)
		if err != nil {
			// User it not a human
			rw.WriteHeader(http.StatusForbidden)
			return
		}
		userId = cookie.Id
	}

	reqDur := req.Form.Get("session-duration")
	stack := req.Form.Get("stack")
	stackName := req.Form.Get("stack_name")
	imageName := req.Form.Get("image_name")

	if stack != "" {
		stack = formatStack(stack)
		if ok, err := stackExists(stack); err != nil {
			log.Printf("Error retrieving stack: %s", err)
			rw.WriteHeader(http.StatusInternalServerError)
			return
		} else if !ok {
			log.Printf("Stack [%s] could not be found", stack)
			rw.WriteHeader(http.StatusBadRequest)
			return
		}

	}
	duration := config.GetDuration(reqDur)
	s, err := core.SessionNew(userId, duration, stack, stackName, imageName)
	if err != nil {
		if provisioner.OutOfCapacity(err) {
			http.Redirect(rw, req, "/ooc", http.StatusFound)
			return
		}
		log.Println(err)
		http.Redirect(rw, req, "/500", http.StatusInternalServerError)
		return
		//TODO: Return some error code
	} else {
		hostname := req.Host
		if config.PWDCName != "" {
			hostname = fmt.Sprintf("%s.%s", config.PWDCName, req.Host)
		}
		// If request is not a form, return sessionId in the body
		if req.Header.Get("X-Requested-With") == "XMLHttpRequest" {
			resp := NewSessionResponse{SessionId: s.Id, Hostname: hostname}
			rw.Header().Set("Content-Type", "application/json")
			json.NewEncoder(rw).Encode(resp)
			return
		}

		http.Redirect(rw, req, fmt.Sprintf("/p/%s", s.Id), http.StatusFound)
	}
}

func formatStack(stack string) string {
	if !strings.HasSuffix(stack, ".yml") {
		// If it doesn't end with ".yml", assume it hasn't been specified, then default to "stack.yml"
		stack = path.Join(stack, "stack.yml")
	}
	if strings.HasPrefix(stack, "/") {
		// The host is anonymous, then use our own stack repo.
		stack = fmt.Sprintf("%s%s", "https://raw.githubusercontent.com/play-with-docker/stacks/master", stack)
	}
	return stack
}

func stackExists(stack string) (bool, error) {
	resp, err := http.Head(stack)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	return resp.StatusCode == 200, nil
}
