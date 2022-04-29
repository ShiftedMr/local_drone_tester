// Copyright 2019 the Drone Authors. All rights reserved.
// Use of this source code is governed by the Blue Oak Model License
// that can be found in the LICENSE file.

package plugin

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/drone/drone-go/plugin/validator"
	"github.com/sirupsen/logrus"
)

// New returns a new validator plugin.
func New(PassString string) validator.Plugin {
	return &plugin{
		PassString,
	}
}

type plugin struct {
	// TODO replace or remove these configuration
	// parameters. They are for demo purposes only.
	passString string
}

func (p *plugin) Validate(ctx context.Context, req *validator.Request) error {
	// TODO replace or remove these checks
	// They are for demo purposes only.
	logrus.Info(fmt.Sprintf("build message: %s", req.Build.Message))
	logrus.Info(fmt.Sprintf("ideal message: %s", p.passString))
	logrus.Info(fmt.Sprintf("compare message: %v", strings.Contains(req.Build.Message, p.passString)))
	if !strings.Contains(req.Build.Message, p.passString) {
		return errors.New("validator: commit message did not contain correct string")
	}

	// a nil error indicates the configuration is valid.
	return nil
}
