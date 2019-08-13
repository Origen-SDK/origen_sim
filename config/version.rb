module OrigenSim
  MAJOR = 0
  MINOR = 20
  BUGFIX = 6
  DEV = nil
  VERSION = [MAJOR, MINOR, BUGFIX].join(".") + (DEV ? ".pre#{DEV}" : '')
end
