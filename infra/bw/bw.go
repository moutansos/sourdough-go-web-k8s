package bw

import (
	"fmt"
	"os"
	"strings"

	bitwarden "github.com/bitwarden/sdk-go"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const BW_ORG_ID = "f329a0e7-4bfd-4a0b-8e6c-b2400076524b"

type BwCtx struct {
	client    bitwarden.BitwardenClientInterface
	secretMap map[string]string
}

func InitBw() (*BwCtx, error) {
	secretMap := make(map[string]string)

	bwAccessToken := os.Getenv("BW_ACCESS_TOKEN")
	bwClient, err := bitwarden.NewBitwardenClient(nil, nil)
	if err != nil {
		return nil, err
	}
	err = bwClient.AccessTokenLogin(bwAccessToken, nil)
	if err != nil {
		return nil, err
	}

	fmt.Println("Loading secrets...")
	secrets, err := bwClient.Secrets().List(BW_ORG_ID)
	if err != nil {
		return nil, err
	}

	for _, secret := range secrets.Data {
		fullSecret, err := bwClient.Secrets().Get(secret.ID)

		if err != nil {
			return nil, err
		}
		
		secretMap[secret.Key] = fullSecret.Value
	}

	return &BwCtx{
		client:  bwClient,
		secretMap: secretMap,
	}, nil
}

func (ctx *BwCtx) Close() {
	ctx.client.Close()
}

func (ctx *BwCtx) GetByName(secretName string) (string, error) {
	fmt.Printf("Getting secret %s...\n", secretName)

	if ctx == nil || ctx.secretMap == nil {
		return "", fmt.Errorf("Error, this context has not been initialized")
	}

	val, ok := ctx.secretMap[secretName]
	if !ok {
		return "", fmt.Errorf("The secret with a key %s was not found!\n", secretName)
	}

	return val, nil

}

func (ctx *BwCtx) GetByEnvAndName(stackName string, secretName string) (string, error) {
	upperStack := strings.ToUpper(stackName)
	fullKeyName := fmt.Sprintf("%s_%s", upperStack, secretName)
	result, err := ctx.GetByName(fullKeyName)

	if err != nil {
		return "", err
	}

	return result, nil
}

func (ctx *BwCtx) BuildEnvVar(stackName string, secretName string) (*corev1.EnvVarArgs, error) {
	foundValue, err := ctx.GetByEnvAndName(stackName, secretName)
	if err != nil {
		return nil, err
	}

	envVar := &corev1.EnvVarArgs{
		Name:  pulumi.String(secretName),
		Value: pulumi.String(foundValue),
	}

	return envVar, nil
}
