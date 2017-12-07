module OrigenSim
  MAJOR = 0
  MINOR = 5
  BUGFIX = 5
  DEV = nil

  VERSION = [MAJOR, MINOR, BUGFIX].join(".") + (DEV ? ".pre#{DEV}" : '')
end
