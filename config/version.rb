module OrigenSim
  MAJOR = 0
  MINOR = 16
  BUGFIX = 0
  DEV = 1

  VERSION = [MAJOR, MINOR, BUGFIX].join(".") + (DEV ? ".pre#{DEV}" : '')
end
