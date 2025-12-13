package main

import (
	"fmt"

	"code.msyke.dev/mSyke/sourdough-go-web-k8s/common"
	"code.msyke.dev/mSyke/sourdough-go-web-k8s/infra/bw"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	appsv1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/apps/v1"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		stackName := ctx.Stack()
		bw, err := bw.InitBw()
		if err != nil {
			return err
		}
	
		//TODO: Replace all instances of the app name with the comon variable for ease of swapping
		containerTag, ctExists := ctx.GetConfig(fmt.Sprintf("%s-infra:containerTag", common.APP_NAME))
		fmt.Printf("ContainerTag: %s\n", containerTag)
		if !ctExists {
			return fmt.Errorf("The pulumi config containerTag does not exist!")
		}

		containerImageName := fmt.Sprintf("code.msyke.dev/private/%s:%s", common.APP_NAME, containerTag)

		namespace, nsExists := ctx.GetConfig(fmt.Sprintf("%s-infra:namespace", common.APP_NAME))
		if !nsExists {
			return fmt.Errorf("The pulumi config namespace does not exist!")
		}

		kubeConfig, err := bw.GetByEnvAndName(stackName, common.KUBECONFIG)
		if err != nil {
			return err
		}

		fmt.Println("Creating Kubernetes Provider...")
		k8sProvider, err := kubernetes.NewProvider(ctx, "msykek8s1", &kubernetes.ProviderArgs{
			Kubeconfig: pulumi.String(kubeConfig),
		})
		if err != nil {
			return err
		}

		_, err = appsv1.NewDeployment(ctx, fmt.Sprintf("%s-deployment", common.APP_NAME), &appsv1.DeploymentArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name: pulumi.String(common.APP_NAME),
				Labels: pulumi.StringMap{
					"app": pulumi.String(common.APP_NAME),
				},
				Namespace: pulumi.String(namespace),
			},
			Spec: &appsv1.DeploymentSpecArgs{
				Replicas: pulumi.Int(2),
				Selector: &metav1.LabelSelectorArgs{
					MatchLabels: pulumi.StringMap{
						"app": pulumi.String(common.APP_NAME),
					},
				},
				Template: &corev1.PodTemplateSpecArgs{
					Metadata: &metav1.ObjectMetaArgs{
						Labels: pulumi.StringMap{
							"app": pulumi.String(common.APP_NAME),
						},
					},
					Spec: &corev1.PodSpecArgs{
						Containers: &corev1.ContainerArray{
							&corev1.ContainerArgs{
								Image: pulumi.String(containerImageName),
								Name:  pulumi.String(common.APP_NAME),
								Ports: &corev1.ContainerPortArray{
									&corev1.ContainerPortArgs{
										ContainerPort: pulumi.Int(common.INTERNAL_CONTAINER_PORT),
									},
								},
								Env: &corev1.EnvVarArray{
									&corev1.EnvVarArgs{
										Name:  pulumi.String(common.APP_ENV),
										Value: pulumi.String(stackName),
									},
								},
							},
						},
						ImagePullSecrets: &corev1.LocalObjectReferenceArray{
							&corev1.LocalObjectReferenceArgs{
								Name: pulumi.String("gitea-image-pull-secret"),
							},
						},
					},
				},
			},
		}, pulumi.Provider(k8sProvider))

		if err != nil {
			return err
		}

		_, err = corev1.NewService(ctx, fmt.Sprintf("%s-service", common.APP_NAME), &corev1.ServiceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String(common.APP_NAME),
				Namespace: pulumi.String(namespace),
			},
			Spec: &corev1.ServiceSpecArgs{
				Ports: &corev1.ServicePortArray{
					&corev1.ServicePortArgs{
						Port:       pulumi.Int(80),
						Protocol:   pulumi.String("TCP"),
						TargetPort: pulumi.Int(common.INTERNAL_CONTAINER_PORT),
					},
				},
				Selector: pulumi.StringMap{
					"app": pulumi.String(common.APP_NAME),
				},
				Type: pulumi.String("ClusterIP"),
			},
		}, pulumi.Provider(k8sProvider))

		if err != nil {
			return err
		}

		return nil
	})
}
