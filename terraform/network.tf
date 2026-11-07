# ---------- Список зон доступності регіону (a, b, c) ----------
data "aws_availability_zones" "available" {
  state = "available"
}

# ---------- VPC: наша власна приватна мережа в AWS ----------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # усі адреси від 10.0.0.0 до 10.0.255.255
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# ---------- Internet Gateway: "двері" мережі в інтернет ----------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id # залежність: спершу створиться VPC

  tags = { Name = "${var.project}-igw" }
}

# ---------- Публічні підмережі (2 штуки, у двох зонах) ----------
# Тут житиме застосунок. Вони мають маршрут в інтернет.
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index) # 10.0.0.0/24, 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${count.index + 1}" }
}

# ---------- Приватні підмережі (2 штуки, у двох зонах) ----------
# Тут житиме база даних. Маршруту в інтернет у них НЕМАЄ.
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10) # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.project}-private-${count.index + 1}" }
}

# ---------- Таблиця маршрутів для публічних підмереж ----------
# Правило: весь трафік назовні (0.0.0.0/0) йде через Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
