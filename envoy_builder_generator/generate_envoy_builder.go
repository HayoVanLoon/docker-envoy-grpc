package main

import (
	"flag"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"text/template"
)

type buildScript struct {
	Tag        string
	Parameters []parameter
	YamlFile   string
}

func (b buildScript) YamlData() string {
	bs, err := ioutil.ReadFile(b.YamlFile)
	if err != nil {
		log.Fatal(err)
	}
	return string(bs)
}

func (b buildScript) SortedParams() []parameter {
	xs := make([]parameter, len(b.Parameters))
	i := 0
	for _, x := range b.Parameters {
		if x.Required {
			xs[i] = x
			i += 1
		}
	}
	for _, x := range b.Parameters {
		if !x.Required {
			xs[i] = x
			i += 1
		}
	}
	return xs
}

type parameter struct {
	Names        []string
	Parameter    string
	Description  string
	Variable     string
	DefaultValue interface{}
	FixedValue   interface{}
	Required     bool
	Runtime      bool
}

func (p parameter) NamesFormatted() string {
	return strings.Join(p.Names, "|")
}

func imageName(tag string) parameter {
	p := parameter{
		Names:       []string{"--image-name"},
		Parameter:   "IMAGE_NAME",
		Description: "Name to use for image.",
		Variable:    "IMAGE_NAME",
	}
	if tag != "" {
		p.DefaultValue = "envoy-static-grpc:" + tag
	}
	return p
}

func debug() parameter {
	return parameter{
		Names:       []string{"--debug"},
		Description: "Activate debug mode. Debug mode keeps build artefacts.",
		Variable:    "DEBUG",
		FixedValue:  1,
	}
}

func descriptor() parameter {
	return parameter{
		Names:        []string{"-d", "--descriptor"},
		Parameter:    "DESCRIPTOR",
		Description:  "gRPC descriptor file.",
		Variable:     "DESCRIPTOR",
		DefaultValue: "descriptor.pb",
	}
}

func listenerPort(port int) parameter {
	p := parameter{
		Names:       []string{"--lp"},
		Parameter:   "LISTENER_PORT",
		Description: "Default proxy listening port.",
		Variable:    "LISTENER_PORT",
		Runtime:     true,
	}
	if port > 0 {
		p.DefaultValue = port
	}
	return p
}

func endpointAddress() parameter {
	return parameter{
		Names:       []string{"--endpoint-address"},
		Parameter:   "ENDPOINT_ADDRESS",
		Description: "Proxy forwarding address.",
		Variable:    "ENDPOINT_ADDRESS",
		Required:    true,
		Runtime:     true,
	}
}

func endpointPort(port int) parameter {
	p := parameter{
		Names:       []string{"--endpoint-port"},
		Parameter:   "ENDPOINT_PORT",
		Description: "Default proxy forwarding port.",
		Variable:    "ENDPOINT_PORT",
		Runtime:     true,
	}
	if port > 0 {
		p.DefaultValue = port
	}
	return p
}

func scriptLocal(tag, conf string) buildScript {
	return buildScript{
		Tag: tag,
		Parameters: []parameter{
			imageName(tag),
			descriptor(),
			debug(),
			listenerPort(10000),
			endpointPort(8080),
		},
		YamlFile: conf,
	}
}

func scriptSimpleJwt(tag, conf string) buildScript {
	return buildScript{
		Tag: tag,
		Parameters: []parameter{
			imageName(tag),
			descriptor(),
			debug(),
			listenerPort(8080),
			endpointAddress(),
		},
		YamlFile: conf,
	}
}

func scriptSimpleTls(tag, conf string) buildScript {
	return buildScript{
		Tag: tag,
		Parameters: []parameter{
			imageName(tag),
			descriptor(),
			debug(),
			listenerPort(8080),
			endpointAddress(),
		},
		YamlFile: conf,
	}
}

func main() {
	var tag, conf string
	flag.StringVar(&tag, "tag", "", "image tag")
	flag.StringVar(&conf, "conf", "config.yaml", "envoy configuration yaml (with placeholders)")
	flag.Parse()
	if tag == "" {
		log.Fatal("need -tag TAG")
	}

	tmpl, err := template.New("build.sh").Parse(buildScriptTemplate)
	if err != nil {
		log.Fatal(err)
	}

	var data buildScript
	switch tag {
	case "local":
		data = scriptLocal(tag, conf)
	case "simple-jwt":
		data = scriptSimpleJwt(tag, conf)
	case "simple-tls":
		data = scriptSimpleTls(tag, conf)
	}

	if err := tmpl.Execute(os.Stdout, data); err != nil {
		log.Fatal(err)
	}
}
