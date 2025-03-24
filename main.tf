locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    project = var.name_prefix
    managed_by = "Terraform"
  }
}

data "aws_availability_zones" "available" {}

module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "~>5.0"

    name                  = var.name_prefix
    cidr                  = var.vpc_cidr
    secondary_cidr_blocks = var.secondary_cidr_blocks

    azs = local.azs

    private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 2, k)]
    public_subnets  = [for k, v in local.azs : cidrsubnet(var.secondary_cidr_blocks.0, 2, k)]
    intra_subnets   = [for k, v in local.azs : cidrsubnet(var.secondary_cidr_blocks.1, 2, k)]

    map_public_ip_on_launch = true
    enable_nat_gateway      = true
    single_nat_gateway      = true
    create_egress_only_igw  = true

    public_subnet_tags = {
        "subnet-type"            = "public"
    
        # 外向けの ELB はこちらの Subnet を利用
        "kubernetes.io/role/elb" = 1
    }

    private_subnet_tags = {
        "subnet-type"            = "private"
    
        # 内向けの ELB はこちらの Subnet を利用
        "kubernetes.io/role/internal-elb" = 1
    }

    tags = local.tags

}


# Managed Node に ssh 用の鍵を生成
module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "~> 2.0"

  key_name_prefix    = var.name_prefix
  create_private_key = true

  tags = local.tags
}

# VPC の CIDR から ssh を許可する firewall ルールを定義

resource "aws_security_group" "remote_access" {
  name_prefix = "${var.name_prefix}-remote-access"
  description = "Allow remote SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-remote" })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                   = var.name_prefix
  cluster_version                = var.eks_version
  cluster_endpoint_public_access = true
  cluster_ip_family              = "ipv4"
  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  control_plane_subnet_ids       = module.vpc.intra_subnets
  create_kms_key                 = false
  cluster_encryption_config      = {}
  enable_irsa                    = true
  
  # EKS addon をこちらで install
  # 利用可能な addon 一覧はこのコマンドから確認することができる
  # $ aws eks describe-addon-versions  \
  # --query 'sort_by(addons &owner)[].{publisher: publisher, owner: owner, addonName: addonName, type: type}' \
  # --output table
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          // must enable this if pod is running in private subnet and access going out via nat gateway
          AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"

          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  # x86_64 の manged node group を利用する例となりますが、
  # その以外に、AL2_ARM_64 や Fargate なども利用が可能
  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
    # 利用可能なインスタンスタイプはこちらのページから確認することができます https://console.aws.amazon.com/ec2/home?#InstanceTypes:v=3;instanceFamily=t3,t3a;defaultVCPus=%3C%5C=2
    # vpc-cniが有効になっているため、各インスタンスタイプで利用可能なIPアドレスの数を確認する必要があります
    instance_types = ["t3a.medium"]
    subnet_ids     = module.vpc.private_subnets
  }

  eks_managed_node_groups = {
    default_node_group = {
      use_custom_launch_template = false
      disk_size = 20
      remote_access = {
        ec2_ssh_key               = module.key_pair.key_pair_name
        source_security_group_ids = [aws_security_group.remote_access.id]
      }
    }
  }

  # クラスターアクセスエントリ
  # 現在の caller identity を管理者として追加
  enable_cluster_creator_admin_permissions = true

  # 他に EKS にアクセスできる IAM Role/User はこちらで付与することも可能
  # access_entries = {
  #   default = {
  #     kubernetes_groups = []
  #     principal_arn     = "FILL_THIS_PRINCIPAL_ARN"

  #     policy_associations = {
  #       default = {
  #         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
  #         access_scope = {
  #           type = "cluster"
  #         }
  #       }
  #     }
  #   },
  # }

  tags = local.tags
}