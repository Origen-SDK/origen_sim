module OrigenSim
  MAJOR = 0
  MINOR = 20
  BUGFIX = 0
  DEV = 0

  VERSION = [MAJOR, MINOR, BUGFIX].join(".") + (DEV ? ".pre#{DEV}" : '')
end
