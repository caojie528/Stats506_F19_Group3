## Group project - R
##
## Question: Do people diagnosed with diabetes consume less calories in the US?
##
## Author: Bei An (anbei@umich.edu)
## Updated: Dec 5, 2019
# 80: -------------------------------------------------------------------------

# set up
library(foreign)
library(tidyr)
library(plyr)
library(dplyr)
library(corrplot)
library(lme4)

# prepare datasets
DEMO = read.xport("../Data/DEMO_I.XPT")
DIQ = read.xport("../Data/DIQ_I.XPT")
PAQ = read.xport("../Data/PAQ_I.XPT")
DR1 = read.xport("../Data/DR1TOT_I.XPT")
DR2 = read.xport("../Data/DR2TOT_I.XPT")
BMX = read.xport("../Data/BMX_I.XPT")

# Merge all of the relevant variables
dm = join_all(list(DEMO[,c("SEQN", "RIDAGEYR", "RIAGENDR", "RIDEXPRG")],
                   DIQ[,c("SEQN", "DIQ010")],
                   PAQ[,c("SEQN", "PAD615", "PAD630", "PAD680")],
                   DR1[,c("SEQN", "DR1TKCAL")],
                   DR2[,c("SEQN", "DR2TKCAL")],
                   BMX[,c("SEQN", "BMXBMI")]),
              by = "SEQN")
names(dm) = c("SEQN","age","gender","pregnancy","DIQ010",
              "vig_work","mod_work","sed_act","DR1","DR2","bmi")

# create a "not in" operator
`%notin%` = Negate(`%in%`)

# exclude data without diabetes diagnosis
c = c(1,2,3)
dm = dm[-which(dm$DIQ010 %notin% c), ]

# exclude pregnant participants
dm = dm[-which(dm$pregnancy==1), ]

# create a new variable representing diabetes
# 1 - diabetes or borderline
# 0 - non-diabetes
dm$diabetes = ifelse(dm$DIQ010==2, 0, 1)

# create a new variable representing male
# 1 - male
# 0 - female
dm$male = ifelse(dm$gender==1, 1, 0)

# pivot the data into "long" format
# and create a variable representing dietary interview day (1/2)
dm = dm %>%
  pivot_longer(
    cols = starts_with("DR"),
    names_to = "day",
    names_prefix = "DR",
    values_to = "kcal",
    values_drop_na = FALSE
  ) %>%
  arrange(SEQN, day)

# check for missing values for each variable
colSums(is.na(dm))

# `vig_work` and `mod_work` have much more missing values than other variables,
# so it is reasonable to remove them from the data frame.  
# `pregnancy` can also be removed since we only need this variable 
# to filter out pregnant individuals.  
# `DIQ010` and `gender` are now redundant due to the new variables.  

# Note that `age` is top-coded at 80, which means 
# participants aged 80 or older were all recorded as age 80. 
# To avoid inaccurate data, we decided to set an age bound from 12 to 79.

dm = dm %>%
  select(-pregnancy, -vig_work, -mod_work, -DIQ010, -gender) %>%
  filter(age>=12 & age<=79)
dm$day = as.numeric(dm$day)

# remove rows with missing value
dm_final = dm[complete.cases(dm),]
dr1_final = dm_final[dm_final$day==1,]
dr2_final = dm_final[dm_final$day==2,]

# check if the response variable - kcal is normally distributed
# day1
# hist(dm_final[dm_final$day==1, ]$kcal, main = "Day 1")
ggplot(dr1_final, aes(x = kcal)) + 
  geom_histogram(aes(y = ..density..), 
                 bins = 100, 
                 fill = "blue", 
                 alpha = 0.8) + 
  stat_function(fun = dnorm, 
                args = list(mean = mean(dr1_final$kcal), 
                            sd = sd(dr1_final$kcal))) + 
  theme_bw()

# day2
# hist(dm_final[dm_final$day==2, ]$kcal, breaks = 100, main = "Day 2")
ggplot(dr2_final, aes(x = kcal)) + 
  geom_histogram(aes(y = ..density..), 
                 bins = 100, 
                 fill = "blue", 
                 alpha = 0.8) + 
  stat_function(fun = dnorm, 
                args = list(mean = mean(dr2_final$kcal), 
                            sd = sd(dr2_final$kcal))) + 
  theme_bw()

# `kcal` seems to be approximately normal with a longer right tail 
# for both day1 and day2.
# In this case, no transformation would be needed.

# fit a linear regression model for day 1
model = dr1_final %>% lm(formula = kcal ~ age + sed_act + bmi + diabetes + male)
# check collinearity
summary(model)
faraway::vif(model)
#corrplot(cor(dm_final))
corrplot(cor(dr1_final))
# No collinearity found.

# fit a linear mixed model
model2 = dm_final %>% lmer(formula = kcal ~ age + sed_act + bmi + 
                             diabetes + male + (1|SEQN))
summary(model2)

# To do: marginal effect