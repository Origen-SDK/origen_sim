module OrigenSim
  MAJOR = 0
  MINOR = 21
  BUGFIX = 0
  DEV = nil
  VERSION = [MAJOR, MINOR, BUGFIX].join(".") + (DEV ? ".pre#{DEV}" : '')
end
