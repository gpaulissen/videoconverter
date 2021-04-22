import React from "react";
import Table from "react-bootstrap/Table";
import Button from "react-bootstrap/Button";
import ButtonToolbar from "react-bootstrap/ButtonToolbar";
import { observer } from "mobx-react";
import {
  getJobs,
  addJob,
  deleteJob,
  cancel,
  startJob,
  APIURL
} from "./request";
import { Formik } from "formik";
import Form from "react-bootstrap/Form";
import Col from "react-bootstrap/Col";
function HomePage({ conversionsStore }) {
  const fileRef = React.createRef();
  const [file, setFile] = React.useState(null);
  const [fileName, setFileName] = React.useState("");
  const [initialized, setInitialized] = React.useState(false);
  const onChange = event => {
    setFile(event.target.files[0]);
    setFileName(event.target.files[0].name);
  };
  const openFileDialog = () => {
    fileRef.current.click();
  };
  const handleSubmit = async evt => {
    if (!file) {
      return;
    }
    let bodyFormData = new FormData();
    bodyFormData.set("outputFormat", evt.outputFormat);
    bodyFormData.append("video", file);
    await addJob(bodyFormData);
    getConversionJobs();
  };
  const getConversionJobs = async () => {
    const response = await getJobs();
    conversionsStore.setConversions(response.data);
  };
  const deleteConversionJob = async id => {
    await deleteJob(id);
    getConversionJobs();
  };
  const cancelConversionJob = async id => {
    await cancel(id);
    getConversionJobs();
  };
  const startConversionJob = async id => {
    await startJob(id);
    getConversionJobs();
  };
  React.useEffect(() => {
    if (!initialized) {
      getConversionJobs();
      setInitialized(true);
    }
  }, [initialized, getConversionJobs]);
  return (
    <div className="page">
      <h1 className="text-center">Convert Video</h1>
      <Formik onSubmit={handleSubmit} initialValues={{ outputFormat: "mp4" }}>
        {({
          handleSubmit,
          handleChange,
          handleBlur,
          values,
          touched,
          isInvalid,
          errors
        }) => (
          <Form noValidate onSubmit={handleSubmit}>
            <Form.Row>
              <Form.Group
                as={Col}
                md="12"
                controlId="outputFormat"
                defaultValue="mp4"
              >
                <Form.Label>Output Format</Form.Label>
                <Form.Control
                  as="select"
                  value={values.outputFormat || "mp4"}
                  onChange={handleChange}
                  isInvalid={touched.outputFormat && errors.outputFormat}
                >
                  <option value="mov">mov</option>
                  <option value="webm">webm</option>
                  <option value="mp4">mp4</option>
                  <option value="mpeg">mpeg</option>
                  <option value="3gp">3gp</option>
                </Form.Control>
                <Form.Control.Feedback type="invalid">
                  {errors.outputFormat}
                </Form.Control.Feedback>
              </Form.Group>
            </Form.Row>
            <Form.Row>
              <Form.Group as={Col} md="12" controlId="video">
                <input
                  type="file"
                  style={{ display: "none" }}
                  ref={fileRef}
                  onChange={onChange}
                  name="video"
                />
                <ButtonToolbar>
                  <Button
                    className="button"
                    onClick={openFileDialog}
                    type="button"
                  >
                    Upload
                  </Button>
                  <span>{fileName}</span>
                </ButtonToolbar>
              </Form.Group>
            </Form.Row>
            <Button type="submit">Add Job</Button>
          </Form>
        )}
      </Formik>
      <br />
      <Table>
        <thead>
          <tr>
            <th>File Name</th>
            <th>Converted File</th>
            <th>Output Format</th>
            <th>Status</th>
            <th>Start</th>
            <th>Cancel</th>
            <th>Delete</th>
          </tr>
        </thead>
        <tbody>
          {conversionsStore.conversions.map(c => {
            return (
              <tr>
                <td>{c.filePath}</td>
                <td>{c.status}</td>
                <td>{c.outputFormat}</td>
                <td>
                  {c.convertedFilePath ? (
                    <a href={`${APIURL}/${c.convertedFilePath}`}>Open</a>
                  ) : (
                    "Not Available"
                  )}
                </td>
                <td>
                  <Button
                    className="button"
                    type="button"
                    onClick={startConversionJob.bind(this, c.id)}
                  >
                    Start
                  </Button>
                </td>
                <td>
                  <Button
                    className="button"
                    type="button"
                    onClick={cancelConversionJob.bind(this, c.id)}
                  >
                    Cancel
                  </Button>
                </td>
                <td>
                  <Button
                    className="button"
                    type="button"
                    onClick={deleteConversionJob.bind(this, c.id)}
                  >
                    Delete
                  </Button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </Table>
    </div>
  );
}
export default observer(HomePage);
