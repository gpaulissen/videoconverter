const axios = require("axios");
export const APIURL = "http://localhost:3000";
export const getJobs = () => axios.get(`${APIURL}/conversions`);
export const addJob = data =>
  axios({
    method: "post",
    url: `${APIURL}/conversions`,
    data,
    config: { headers: { "Content-Type": "multipart/form-data" } }
  });
export const cancel = id => axios.put(`${APIURL}/conversions/cancel/${id}`, {});
export const deleteJob = id =>
  axios.delete(`${APIURL}/conversions/${id}`);
export const startJob = id => axios.get(`${APIURL}/conversions/start/${id}`);
